package swapip

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"swapip/internal/adapters/logger"
	"swapip/pkg/twoip"
	"time"

	"go.uber.org/zap"
)

type SwapIP struct {
	log      *logger.Logger
	cfg      Config
	server   *http.Server
	authUser map[string]string
}

func New(ctx context.Context, cfg Config, log *logger.Logger) *SwapIP {
	s := &SwapIP{
		log:      log,
		cfg:      cfg,
		authUser: map[string]string{},
	}

	return s
}

func (s *SwapIP) Send() error {
	ipapp := twoip.New()
	ip, err := ipapp.GetIP()
	if err != nil {
		s.log.Error("failed getting remote address", zap.Error(err))
		return fmt.Errorf("failed getting remote address: %w", err)
	}

	ipS := ip.String()
	s.log.Debug("remote address", zap.String("ip", ipS))

	ipStore, err := s.GetIPFromStore()
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("failed proccess: %w", err)
		}
	}
	// если ip не было в хранилище
	// или если текущий не совпадает с хранимым
	// то отправляем новый и сохраняем
	if ipStore == nil || ipStore.String() != ipS {
		if ipStore != nil {
			s.log.Info("storage old", zap.String("ip", ipStore.String()))
		}
		//TODO send
		err = s.sendIPToRemote(ipS)
		if err != nil {
			return fmt.Errorf("failed send ip: %w", err)
		}

		err = s.StoreIP(ipS)
		if err != nil {
			return fmt.Errorf("failed storage ip: %w", err)
		}
		s.log.Info("storage new", zap.String("ip", ipS))
	}

	return nil
}

func (s *SwapIP) sendIPToRemote(ip string) error {
	rBody := struct {
		IP string `json:"ip"`
	}{
		IP: ip,
	}
	bBody, err := json.Marshal(rBody)
	if err != nil {
		return fmt.Errorf("failed marshal body: %w", err)
	}

	r, err := http.NewRequest(http.MethodPost, s.cfg.RemoteAddres, bytes.NewBuffer(bBody))
	if err != nil {
		return fmt.Errorf("failed create request: %w", err)
	}
	r.Header.Add("Content-Type", "application/json")
	r.Header.Add("Authorization", "Basic "+s.cfg.AuthBasic)

	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return fmt.Errorf("failed getting response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("response status not OK")
	}

	return nil
}

func (s *SwapIP) GetIPFromStore() (*netip.Addr, error) {
	_, err := os.Stat(s.cfg.FileIP)
	if err != nil && errors.Is(err, os.ErrNotExist) {
		return nil, errors.Join(err, fmt.Errorf("file `%s` not exists", s.cfg.FileIP))
	}
	f, err := os.Open(s.cfg.FileIP)
	if err != nil {
		return nil, fmt.Errorf("failed create file ip store: %w", err)
	}

	data, err := io.ReadAll(f)
	if err != nil {
		return nil, fmt.Errorf("failed read from ip store: %w", err)
	}
	ip := twoip.CleanIP(string(data))
	addr := netip.MustParseAddr(ip)

	return &addr, nil
}

func (s *SwapIP) StoreIP(ip string) error {
	f, err := os.Create(s.cfg.FileIP)
	if err != nil {
		return fmt.Errorf("failed create file: %w", err)
	}

	_, err = f.Write([]byte(ip))
	if err != nil {
		return fmt.Errorf("failed write ip to file: %w", err)
	}

	return nil
}

func (s *SwapIP) RunServer(ctx context.Context) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	type bodyResponse struct {
		IP string `json:"ip"`
	}
	handler := func(w http.ResponseWriter, r *http.Request) {
		username, password, ok := r.BasicAuth()
		if !ok || !s.verifyUserPass(username, password) {
			w.Header().Set("WWW-Authenticate", `Basic realm="api"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		s.log.Info("info",
			zap.String("remote", r.RemoteAddr),
			zap.String("method", r.Method),
			zap.String("user", username),
		)
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			s.log.Error("failed read body", zap.Error(err))
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		defer r.Body.Close()
		jBody := bodyResponse{}
		err = json.Unmarshal(body, &jBody)
		if err != nil {
			s.log.Error("failed unmarshal body", zap.Error(err))
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		s.log.Info("info", zap.Any("body", jBody))

		//обновляем конфиг
		err = s.rewriteAddress(jBody.IP)
		if err != nil {
			s.log.Error("failed rewrite IPs", zap.Error(err))
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		//перезапускаем nginx
		//делаем в горутине т.к. соединение с сендером прервется
		go func() {
			err = s.execScript()
			if err != nil {
				s.log.Error("failed exec script", zap.Error(err))
				return
			}
			s.log.Info("script executed")
		}()

		err = s.StoreIP(jBody.IP)
		if err != nil {
			s.log.Error("failed storage new ip", zap.Error(err))
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		//если всё ок то возращаем тоже ок иначе 500
		w.Header().Add("Content-Type", "application/json")
		fmt.Fprintf(w, "{\"status\": true}")
	}

	err := s.uploadAuthUser()
	if err != nil {
		return fmt.Errorf("failed upload auth users: %w", err)
	}

	s.server = &http.Server{
		BaseContext:  func(net.Listener) context.Context { return ctx },
		Addr:         s.cfg.Address,
		Handler:      http.HandlerFunc(handler),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	err = s.server.ListenAndServe()
	if err != nil {
		return fmt.Errorf("failed listen and serve: %w", err)
	}

	return nil
}

func (s *SwapIP) ShutdownServer(ctx context.Context) error {
	return s.server.Shutdown(ctx)
}

func (s *SwapIP) uploadAuthUser() error {
	f, err := os.Open("./user.data")
	if err != nil {
		return fmt.Errorf("failed open user file: %w", err)
	}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		text := scanner.Text()
		b, err := base64.StdEncoding.DecodeString(text)
		if err != nil {
			return fmt.Errorf("failed read user file: %w", err)
		}
		split := strings.Split(string(b), ":")
		if len(split) < 2 {
			return fmt.Errorf("failed user data")
		}

		s.authUser[split[0]] = split[1]
	}
	return nil
}

func (s *SwapIP) verifyUserPass(username, password string) bool {
	if v, ok := s.authUser[username]; ok && v == password {
		return true
	}

	return false
}

func (s *SwapIP) execScript() error {
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("cmd.exe", "/C", s.cfg.Script)
	} else {
		cmd = exec.Command("/bin/sh", s.cfg.Script)
	}
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed exec script: %w", err)
	}

	return nil
}

func (s *SwapIP) rewriteAddress(newIP string) error {
	list := s.cfg.NginxConfFiles.Strings()
	var errlist error
	ip, err := s.GetIPFromStore()
	if err != nil {
		return fmt.Errorf("failed getting ip from store: %w", err)
	}
	for _, l := range list {
		func() {
			f, err := os.Open(l)
			if err != nil {
				errlist = errors.Join(errlist, fmt.Errorf("failed open file `%s`: %w", l, err))
				return
			}

			b, err := io.ReadAll(f)
			if err != nil {
				errlist = errors.Join(errlist, fmt.Errorf("failed read file `%s`: %w", l, err))
				return
			}
			f.Close()

			text := string(b)
			text = strings.ReplaceAll(text, ip.String(), newIP)

			f, err = os.Create(l)
			if err != nil {
				errlist = errors.Join(errlist, fmt.Errorf("failed create file `%s`: %w", l, err))
				return
			}
			defer f.Close()
			_, err = f.Write([]byte(text))
			if err != nil {
				errlist = errors.Join(errlist, fmt.Errorf("failed write file `%s`: %w", l, err))
				return
			}
		}()

	}
	return errlist
}
