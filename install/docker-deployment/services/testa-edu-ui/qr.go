package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
)

type QRResult struct {
	JSONXTUri   string `json:"jsonxtUri"`
	QRData      string `json:"qrData"`
	QRPngBase64 string `json:"qrPngBase64"`
	Sizes       struct {
		JSONLD int `json:"jsonld"`
		JSONXT int `json:"jsonxt"`
		QRData int `json:"qrData"`
		QRPng  int `json:"qrPng"`
	} `json:"sizes"`
}

func generateQR(signedCredential json.RawMessage) (*QRResult, error) {
	scriptPath := filepath.Join(config.ScriptsDir, "qr-encode.js")
	cmd := exec.Command(config.NodeBin, scriptPath)
	cmd.Stdin = bytes.NewReader(signedCredential)
	cmd.Dir = config.ScriptsDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		errMsg := stderr.String()
		if errMsg == "" {
			errMsg = err.Error()
		}
		return nil, fmt.Errorf("QR generation failed: %s", errMsg)
	}

	var result QRResult
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		return nil, fmt.Errorf("parsing QR result: %w", err)
	}

	return &result, nil
}
