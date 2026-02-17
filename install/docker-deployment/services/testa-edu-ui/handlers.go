package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"
)

type Session struct {
	Form             CredentialForm
	Token            string
	SignedCredential json.RawMessage
	Verified         bool
	VerifyMessage    string
	QR               *QRResult
	CreatedAt        time.Time
}

var (
	sessions   = make(map[string]*Session)
	sessionsMu sync.RWMutex
)

func init() {
	// Clean up old sessions every 30 minutes
	go func() {
		for {
			time.Sleep(30 * time.Minute)
			sessionsMu.Lock()
			for id, s := range sessions {
				if time.Since(s.CreatedAt) > time.Hour {
					delete(sessions, id)
				}
			}
			sessionsMu.Unlock()
		}
	}()
}

func newSessionID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func getSession(r *http.Request) *Session {
	cookie, err := r.Cookie("sid")
	if err != nil {
		return nil
	}
	sessionsMu.RLock()
	defer sessionsMu.RUnlock()
	return sessions[cookie.Value]
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok"}`))
}

func handleIndex(w http.ResponseWriter, r *http.Request) {
	if err := tmpl.ExecuteTemplate(w, "layout", nil); err != nil {
		log.Printf("template error: %v", err)
		http.Error(w, "Internal error", 500)
	}
}

func handleIssueStart(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		tmpl.ExecuteTemplate(w, "error", "Invalid form data")
		return
	}

	form := CredentialForm{
		StudentName:    r.FormValue("studentName"),
		Institution:    r.FormValue("institution"),
		Degree:         r.FormValue("degree"),
		FieldOfStudy:   r.FormValue("fieldOfStudy"),
		EnrollmentDate: r.FormValue("enrollmentDate"),
		GraduationDate: r.FormValue("graduationDate"),
		StudentID:      r.FormValue("studentId"),
		GPA:            r.FormValue("gpa"),
		Honors:         r.FormValue("honors"),
	}

	if form.StudentName == "" || form.Institution == "" || form.Degree == "" {
		tmpl.ExecuteTemplate(w, "error", "Student name, institution, and degree are required")
		return
	}

	sid := newSessionID()
	sessionsMu.Lock()
	sessions[sid] = &Session{Form: form, CreatedAt: time.Now()}
	sessionsMu.Unlock()

	http.SetCookie(w, &http.Cookie{
		Name:     "sid",
		Value:    sid,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})

	data := map[string]interface{}{"Form": form}
	if err := tmpl.ExecuteTemplate(w, "progress", data); err != nil {
		log.Printf("template error: %v", err)
	}
}

func handleStepToken(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil {
		tmpl.ExecuteTemplate(w, "step-token", map[string]interface{}{"Error": "Session expired. Please start over."})
		return
	}

	agent := NewAgentClient(config.AgentURL, config.APIKey)
	token, err := agent.GetToken()
	if err != nil {
		log.Printf("token error: %v", err)
		tmpl.ExecuteTemplate(w, "step-token", map[string]interface{}{"Error": err.Error()})
		return
	}

	sessionsMu.Lock()
	sess.Token = token
	sessionsMu.Unlock()

	tmpl.ExecuteTemplate(w, "step-token", map[string]interface{}{"Success": true})
}

func handleStepSign(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil {
		tmpl.ExecuteTemplate(w, "step-sign", map[string]interface{}{"Error": "Session expired. Please start over."})
		return
	}

	payload := buildCredentialPayload(sess.Form, config.IssuerDID)
	agent := NewAgentClient(config.AgentURL, config.APIKey)
	signed, err := agent.SignCredential(sess.Token, payload)
	if err != nil {
		log.Printf("sign error: %v", err)
		tmpl.ExecuteTemplate(w, "step-sign", map[string]interface{}{"Error": err.Error()})
		return
	}

	sessionsMu.Lock()
	sess.SignedCredential = signed
	sessionsMu.Unlock()

	tmpl.ExecuteTemplate(w, "step-sign", map[string]interface{}{"Success": true})
}

func handleStepVerify(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil {
		tmpl.ExecuteTemplate(w, "step-verify", map[string]interface{}{"Error": "Session expired. Please start over."})
		return
	}

	agent := NewAgentClient(config.AgentURL, config.APIKey)
	verified, msg, err := agent.VerifyCredential(sess.Token, sess.SignedCredential)
	if err != nil {
		log.Printf("verify error: %v", err)
		tmpl.ExecuteTemplate(w, "step-verify", map[string]interface{}{"Error": err.Error()})
		return
	}

	sessionsMu.Lock()
	sess.Verified = verified
	sess.VerifyMessage = msg
	sessionsMu.Unlock()

	tmpl.ExecuteTemplate(w, "step-verify", map[string]interface{}{
		"Verified": verified,
		"Message":  msg,
	})
}

func handleStepQR(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil {
		tmpl.ExecuteTemplate(w, "step-qr", map[string]interface{}{"Error": "Session expired. Please start over."})
		return
	}

	qr, err := generateQR(sess.SignedCredential)
	if err != nil {
		log.Printf("QR error: %v", err)
		tmpl.ExecuteTemplate(w, "step-qr", map[string]interface{}{"Error": err.Error()})
		return
	}

	sessionsMu.Lock()
	sess.QR = qr
	sessionsMu.Unlock()

	// Pretty-print the credential JSON for display
	var prettyJSON bytes.Buffer
	json.Indent(&prettyJSON, sess.SignedCredential, "", "  ")

	tmpl.ExecuteTemplate(w, "step-qr", map[string]interface{}{
		"QRPngBase64":    qr.QRPngBase64,
		"CredentialJSON": prettyJSON.String(),
		"Sizes": map[string]int{
			"JSONXT": qr.Sizes.JSONXT,
			"QRData": qr.Sizes.QRData,
		},
	})
}

func handleDownloadQRPNG(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil || sess.QR == nil {
		http.Error(w, "No QR code available. Please issue a credential first.", http.StatusNotFound)
		return
	}

	pngData, err := base64.StdEncoding.DecodeString(sess.QR.QRPngBase64)
	if err != nil {
		http.Error(w, "Failed to decode QR image", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Content-Disposition", "attachment; filename=\"testa-edu-credential-qr.png\"")
	w.Write(pngData)
}

func handleDownloadJSON(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil || sess.SignedCredential == nil {
		http.Error(w, "No credential available. Please issue a credential first.", http.StatusNotFound)
		return
	}

	var prettyJSON bytes.Buffer
	json.Indent(&prettyJSON, sess.SignedCredential, "", "  ")

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Disposition", "attachment; filename=\"testa-edu-credential.json\"")
	w.Write(prettyJSON.Bytes())
}

func handleDownloadJSONXT(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil || sess.QR == nil {
		http.Error(w, "No credential available. Please issue a credential first.", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"testa-edu-credential.jsonxt\"")
	w.Write([]byte(sess.QR.JSONXTUri))
}

func handleDownloadPDF(w http.ResponseWriter, r *http.Request) {
	sess := getSession(r)
	if sess == nil || sess.SignedCredential == nil {
		http.Error(w, "No credential available. Please issue a credential first.", http.StatusNotFound)
		return
	}

	pdfBytes, err := generatePDF(sess)
	if err != nil {
		log.Printf("PDF error: %v", err)
		http.Error(w, "Failed to generate PDF", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", "attachment; filename=\"testa-edu-credential.pdf\"")
	w.Write(pdfBytes)
}
