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

	// mtr 0.96 doesn't support JSON, use CSV instead
	cmd := exec.Command(mtrBin, "-r", "-c", fmt.Sprintf("%d", count), "-n", dest)
	out, err := cmd.Output()
	if err != nil {
		fmt.Printf("[mtr-runner] ERROR: mtr failed for %s: %v\n", dest, err)
		return
	}

	// Parse CSV output and convert to JSON
	data := parseMTRCSV(string(out))
	pretty, _ := json.MarshalIndent(data, "", "  ")
	os.WriteFile(outfile, pretty, 0644)
}

func parseMTRCSV(csv string) map[string]interface{} {
	lines := strings.Split(strings.TrimSpace(csv), "\n")
	if len(lines) < 1 {
		return map[string]interface{}{"error": "no output"}
	}

	// Parse header
	headers := strings.Fields(strings.TrimSpace(lines[0]))
	if len(headers) < 8 {
		return map[string]interface{}{"error": "invalid output format"}
	}

	// Parse data rows
	var hops []map[string]interface{}
	for i := 1; i < len(lines); i++ {
		fields := strings.Fields(strings.TrimSpace(lines[i]))
		if len(fields) < len(headers) {
			continue
		}

		hop := make(map[string]interface{})
		for j, h := range headers {
			hop[h] = fields[j]
		}
		hops = append(hops, hop)
	}

	return map[string]interface{}{
		"destination": strings.Split(lines[len(lines)-1], " ")[0],
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
		"hops":      hops,
	}
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
