package main

import (
	"html/template"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

type Config struct {
	Port       string
	AgentURL   string
	APIKey     string
	IssuerDID  string
	NodeBin    string
	ScriptsDir string
}

var (
	config Config
	tmpl   *template.Template
)

func main() {
	config = loadConfig()

	tmpl = template.Must(template.ParseGlob(filepath.Join("templates", "*.html")))
	tmpl = template.Must(tmpl.ParseGlob(filepath.Join("templates", "partials", "*.html")))

	mux := http.NewServeMux()

	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))

	mux.HandleFunc("GET /{$}", handleIndex)
	mux.HandleFunc("GET /health", handleHealth)

	mux.HandleFunc("POST /issue", handleIssueStart)
	mux.HandleFunc("POST /step/token", handleStepToken)
	mux.HandleFunc("POST /step/sign", handleStepSign)
	mux.HandleFunc("POST /step/verify", handleStepVerify)
	mux.HandleFunc("POST /step/qr", handleStepQR)

	mux.HandleFunc("GET /download/qr.png", handleDownloadQRPNG)
	mux.HandleFunc("GET /download/credential.pdf", handleDownloadPDF)
	mux.HandleFunc("GET /download/credential.json", handleDownloadJSON)
	mux.HandleFunc("GET /download/credential.jsonxt", handleDownloadJSONXT)

	log.Printf("Testa Edu UI starting on :%s", config.Port)
	log.Fatal(http.ListenAndServe(":"+config.Port, mux))
}

func loadConfig() Config {
	return Config{
		Port:       envOr("PORT", "3002"),
		AgentURL:   envOr("AGENT_URL", "http://host.docker.internal:8004"),
		APIKey:     envOr("API_KEY", "supersecret-that-too-16chars"),
		IssuerDID:  envOr("ISSUER_DID", "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd"),
		NodeBin:    envOr("NODE_BIN", "node"),
		ScriptsDir: envOr("SCRIPTS_DIR", "./scripts"),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
