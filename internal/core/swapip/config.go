package swapip

import (
	"bufio"
	"os"
	"strings"
	"time"
)

type stringList string

type Config struct {
	RemoteAddress    string        `env:"SENDER_REMOTE_ADDRESS"`
	FileIP           string        `env:"STORAGE_IP" envDefault:"ip.data"`
	Address          string        `env:"RECEPIENT_ADDRESS" envDefault:":8080"`
	NginxConfFiles   stringList    `env:"RECEPIENT_NGINX_CONF"` // путь к файлу со списком конфигурационных файлов nginx (каждый путь на новой строке)
	Script           string        `env:"RECEPIENT_SCRIPT"`
	AuthBasic        string        `env:"SENDER_BASIC_AUTH"`
	UserDataFile     string        `env:"RECEPIENT_USER_DATA" envDefault:"./user.data"`
	HTTPClientTimeout time.Duration `env:"HTTP_CLIENT_TIMEOUT" envDefault:"30s"`
}

// ReadFiles читает файл, путь которого содержится в stringList,
// и возвращает список строк (путей к конфигурационным файлам nginx),
// по одному на каждой строке. Пустые строки и строки, начинающиеся с '#', игнорируются.
func (s stringList) ReadFiles() ([]string, error) {
	path := string(s)
	if path == "" {
		return nil, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var lines []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		lines = append(lines, line)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return lines, nil
}
