package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func getEnv(key, def string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	return v
}

func sanitize(dest string) string {
	r := strings.NewReplacer(".", "-", ":", "-", "/", "-")
	return r.Replace(dest)
}

func runMTR(mtrBin, dest string, count int, outputPath string) {
	ts := time.Now().UTC().Format("20060102T150405Z")
	outfile := filepath.Join(outputPath, fmt.Sprintf("%s_%s.json", ts, sanitize(dest)))
	fmt.Printf("[mtr-runner] Running mtr to %s -> %s\n", dest, outfile)

	cmd := exec.Command(mtrBin, "-j", "-c", fmt.Sprintf("%d", count), dest)
	out, err := cmd.Output()
	if err != nil {
		fmt.Printf("[mtr-runner] ERROR: mtr failed for %s: %v\n", dest, err)
		return
	}

	raw := strings.TrimSpace(string(out))
	var parsed interface{}
	if jsonErr := json.Unmarshal([]byte(raw), &parsed); jsonErr != nil {
		fmt.Printf("[mtr-runner] WARNING: Output for %s was not valid JSON\n", dest)
		os.WriteFile(outfile, []byte(raw), 0644)
		return
	}

	pretty, _ := json.MarshalIndent(parsed, "", "  ")
	os.WriteFile(outfile, pretty, 0644)
}

func main() {
	interval := 300
	fmt.Sscanf(getEnv("MTR_INTERVAL", "300"), "%d", &interval)

	count := 10
	fmt.Sscanf(getEnv("MTR_COUNT", "10"), "%d", &count)

	outputPath := getEnv("MTR_OUTPUT_PATH", "/data/mtr")
	mtrBin := getEnv("MTR_BIN", "/usr/bin/mtr")
	rawDests := getEnv("MTR_DESTINATIONS", "1.1.1.1")

	var destinations []string
	for _, d := range strings.Split(rawDests, ",") {
		d = strings.TrimSpace(d)
		if d != "" {
			destinations = append(destinations, d)
		}
	}

	if err := os.MkdirAll(outputPath, 0755); err != nil {
		fmt.Printf("[mtr-runner] ERROR: cannot create output path: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("[mtr-runner] Starting.")
	fmt.Printf("  Interval : %ds\n", interval)
	fmt.Printf("  Count    : %d packets\n", count)
	fmt.Printf("  Output   : %s\n", outputPath)
	fmt.Printf("  Targets  : %v\n", destinations)

	for {
		for _, dest := range destinations {
			runMTR(mtrBin, dest, count, outputPath)
		}
		fmt.Printf("[mtr-runner] Cycle complete. Sleeping %ds...\n", interval)
		time.Sleep(time.Duration(interval) * time.Second)
	}
}
