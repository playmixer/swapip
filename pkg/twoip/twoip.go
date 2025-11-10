package twoip

import (
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"regexp"
)

var (
	base string = "http://2ip.ru"
)

type IP struct {
	ip netip.Addr
}

type TwoIP struct {
}

func New() *TwoIP {
	return &TwoIP{}
}

func (t *TwoIP) GetIP() (*IP, error) {
	r, err := http.NewRequest(http.MethodGet, base, nil)
	if err != nil {
		return nil, fmt.Errorf("failed create request: %w", err)
	}
	r.Header.Add("Content-Type", "text/plain")
	r.Header.Add("User-Agent", "curl/1")

	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return nil, fmt.Errorf("failed getting response: %w", err)
	}
	defer resp.Body.Close()

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
	pattern := regexp.MustCompile(`\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b`)
	ip = pattern.FindString(ip)
	return ip
}
