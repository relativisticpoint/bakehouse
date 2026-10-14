// Command app is the tiny service that Bakehouse builds, ships and runs.
// It exists to be a deployable thing, not to be interesting.
package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

// Set at build time via -ldflags "-X main.version=... -X main.gitSHA=...".
var (
	version = "dev"
	gitSHA  = "unknown"
)

type info struct {
	AppVersion string `json:"app_version"`
	GitSHA     string `json:"git_sha"`
	Env        string `json:"env"`
	AMIID      string `json:"ami_id"`
	InstanceID string `json:"instance_id"`
}

func main() {
	addr := ":8080"
	if p := os.Getenv("PORT"); p != "" {
		addr = ":" + p
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(info{
			AppVersion: version,
			GitSHA:     gitSHA,
			Env:        getenv("APP_ENV", "local"),
			AMIID:      metadata(r.Context(), "AMI_ID", "meta-data/ami-id"),
			InstanceID: metadata(r.Context(), "INSTANCE_ID", "meta-data/instance-id"),
		})
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("bakehouse app %s (%s) listening on %s", version, gitSHA, addr)
	log.Fatal(srv.ListenAndServe())
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// metadata returns the value of an env var override if set, otherwise asks the
// EC2 instance metadata service (IMDSv2), otherwise "unknown" (e.g. on a laptop).
func metadata(ctx context.Context, envKey, path string) string {
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	ctx, cancel := context.WithTimeout(ctx, 500*time.Millisecond)
	defer cancel()

	const base = "http://169.254.169.254/latest/"
	tokenReq, err := http.NewRequestWithContext(ctx, http.MethodPut, base+"api/token", nil)
	if err != nil {
		return "unknown"
	}
	tokenReq.Header.Set("X-aws-ec2-metadata-token-ttl-seconds", "60")
	tokenResp, err := http.DefaultClient.Do(tokenReq)
	if err != nil {
		return "unknown"
	}
	defer tokenResp.Body.Close()
	token, err := io.ReadAll(tokenResp.Body)
	if err != nil || tokenResp.StatusCode != http.StatusOK {
		return "unknown"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+path, nil)
	if err != nil {
		return "unknown"
	}
	req.Header.Set("X-aws-ec2-metadata-token", string(token))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "unknown"
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode != http.StatusOK {
		return "unknown"
	}
	return string(body)
}
