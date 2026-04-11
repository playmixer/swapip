package twoip

import (
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"regexp"
	"time"
)

var (
	base          = "http://2ip.ru"
	ipv4LineRegex = regexp.MustCompile(`\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b`)
)

type IP struct {
	ip netip.Addr
}

type TwoIP struct {
	client *http.Client
}

// New создаёт клиент для запроса внешнего IP. Если client == nil, используется клиент с таймаутом 30 с.
func New(client *http.Client) *TwoIP {
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	return &TwoIP{client: client}
}

func (t *TwoIP) GetIP() (*IP, error) {
	r, err := http.NewRequest(http.MethodGet, base, nil)
	if err != nil {
		return nil, fmt.Errorf("failed create request: %w", err)
	}
	r.Header.Add("Content-Type", "text/plain")
	r.Header.Add("User-Agent", "curl/1")

	resp, err := t.client.Do(r)
	if err != nil {
		return nil, fmt.Errorf("failed getting response: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil, fmt.Errorf("unexpected status: %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed read body: %w", err)
	}

	addr := &IP{}

	ip := CleanIP(string(body))

	addr.ip, err = netip.ParseAddr(ip)
	if err != nil {
		return nil, fmt.Errorf("failed parse ip: %w", err)
	}

	return addr, nil
}

func (ip *IP) String() string {
	return ip.ip.String()
}

func CleanIP(ip string) string {
	return ipv4LineRegex.FindString(ip)
}
