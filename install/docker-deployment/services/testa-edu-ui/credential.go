package main

import (
	"crypto/md5"
	"encoding/hex"
	"time"
)

type CredentialForm struct {
	StudentName    string
	Institution    string
	Degree         string
	FieldOfStudy   string
	EnrollmentDate string
	GraduationDate string
	StudentID      string
	GPA            string
	Honors         string
}

func buildCredentialPayload(form CredentialForm, issuerDID string) map[string]interface{} {
	hash := md5.Sum([]byte(form.StudentName))
	studentDID := "did:example:student:" + hex.EncodeToString(hash[:])[:16]

	subject := map[string]interface{}{
		"id":       studentDID,
		"type":     "EducationCredential",
		"name":     form.StudentName,
		"alumniOf": form.Institution,
		"degree":   form.Degree,
	}
	if form.FieldOfStudy != "" {
		subject["fieldOfStudy"] = form.FieldOfStudy
	}
	if form.EnrollmentDate != "" {
		subject["enrollmentDate"] = form.EnrollmentDate
	}
	if form.GraduationDate != "" {
		subject["graduationDate"] = form.GraduationDate
	}
	if form.StudentID != "" {
		subject["studentId"] = form.StudentID
	}
	if form.GPA != "" {
		subject["gpa"] = form.GPA
	}
	if form.Honors != "" {
		subject["honors"] = form.Honors
	}

	inlineContext := map[string]string{
		"EducationCredential": "https://schema.org/EducationalOccupationalCredential",
		"name":                "https://schema.org/name",
		"alumniOf":            "https://schema.org/alumniOf",
		"degree":              "https://schema.org/educationalCredentialAwarded",
		"fieldOfStudy":        "https://schema.org/programName",
		"enrollmentDate":      "https://schema.org/startDate",
		"graduationDate":      "https://schema.org/endDate",
		"studentId":           "https://schema.org/identifier",
		"gpa":                 "https://schema.org/ratingValue",
		"honors":              "https://schema.org/honorificSuffix",
	}

	return map[string]interface{}{
		"credential": map[string]interface{}{
			"@context": []interface{}{
				"https://www.w3.org/2018/credentials/v1",
				inlineContext,
			},
			"type":              []string{"VerifiableCredential", "EducationCredential"},
			"issuer":            issuerDID,
			"issuanceDate":      time.Now().UTC().Format("2006-01-02T15:04:05Z"),
			"credentialSubject": subject,
		},
		"verificationMethod": issuerDID + "#key-1",
		"proofType":          "EcdsaSecp256k1Signature2019",
	}
}
