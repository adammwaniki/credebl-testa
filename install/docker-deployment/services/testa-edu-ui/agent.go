package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type AgentClient struct {
	BaseURL string
	APIKey  string
	client  *http.Client
}

func NewAgentClient(baseURL, apiKey string) *AgentClient {
	return &AgentClient{
		BaseURL: strings.TrimRight(baseURL, "/"),
		APIKey:  apiKey,
		client:  &http.Client{Timeout: 30 * time.Second},
	}
}

func (a *AgentClient) GetToken() (string, error) {
	req, err := http.NewRequest("POST", a.BaseURL+"/agent/token", nil)
	if err != nil {
		return "", fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Authorization", a.APIKey)

	resp, err := a.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("agent unreachable at %s: %w", a.BaseURL, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("invalid response: %s", string(body))
	}

	token, ok := result["token"].(string)
	if !ok || token == "" {
		return "", fmt.Errorf("no token in response: %s", string(body))
	}

	return token, nil
}

func (a *AgentClient) SignCredential(token string, payload map[string]interface{}) (json.RawMessage, error) {
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshaling payload: %w", err)
	}

	req, err := http.NewRequest("POST",
		a.BaseURL+"/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd",
		bytes.NewReader(payloadBytes))
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := a.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("signing request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}

	// Check for proof in response (indicates success)
	if !bytes.Contains(body, []byte(`"proof"`)) {
		return nil, fmt.Errorf("signing failed: %s", string(body))
	}

	// Extract the inner credential if wrapped
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal(body, &wrapper); err == nil {
		if cred, ok := wrapper["credential"]; ok {
			return cred, nil
		}
	}

	return body, nil
}

func (a *AgentClient) VerifyCredential(token string, signedCred json.RawMessage) (bool, string, error) {
	wrapper := map[string]json.RawMessage{"credential": signedCred}
	payloadBytes, err := json.Marshal(wrapper)
	if err != nil {
		return false, "", fmt.Errorf("marshaling payload: %w", err)
	}

	req, err := http.NewRequest("POST", a.BaseURL+"/agent/credential/verify", bytes.NewReader(payloadBytes))
	if err != nil {
		return false, "", fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := a.client.Do(req)
	if err != nil {
		return false, "", fmt.Errorf("verification request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, "", fmt.Errorf("reading response: %w", err)
	}

	bodyStr := strings.ToLower(string(body))
	verified := strings.Contains(bodyStr, `"verified":true`) ||
		strings.Contains(bodyStr, `"isvalid":true`) ||
		strings.Contains(bodyStr, `"valid":true`)

	return verified, string(body), nil
}
