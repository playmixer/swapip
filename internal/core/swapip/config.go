package swapip

import "strings"

type stringList string

type Config struct {
	RemoteAddres   string     `env:"SENDER_REMOTE_ADDRESS"`
	FileIP         string     `env:"STORAGE_IP" envDefault:"ip.data"`
	Address        string     `env:"RECEPIENT_ADDRESS" envDefault:":8080"`
	NginxConfFiles stringList `env:"RECEPIENT_NGINX_CONF"`
	Script         string     `env:"RECEPIENT_SCRIPT"`
}

func (s stringList) Strings() []string {
	return strings.Split(string(s), ";")
}
