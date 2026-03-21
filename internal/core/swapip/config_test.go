package swapip

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestStringList_ReadFiles(t *testing.T) {
	// Создаём временный файл со списком
	tmpDir := t.TempDir()
	listFile := filepath.Join(tmpDir, "list.txt")
	content := "/etc/nginx/nginx.conf\n/etc/nginx/sites-enabled/default\n# комментарий\n\n"
	if err := os.WriteFile(listFile, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	sl := stringList(listFile)
	got, err := sl.ReadFiles()
	if err != nil {
		t.Fatalf("ReadFiles() error = %v", err)
	}
	want := []string{"/etc/nginx/nginx.conf", "/etc/nginx/sites-enabled/default"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("ReadFiles() = %v, want %v", got, want)
	}
}

func TestStringList_ReadFiles_Empty(t *testing.T) {
	tmpDir := t.TempDir()
	listFile := filepath.Join(tmpDir, "empty.txt")
	if err := os.WriteFile(listFile, []byte(""), 0644); err != nil {
		t.Fatal(err)
	}

	sl := stringList(listFile)
	got, err := sl.ReadFiles()
	if err != nil {
		t.Fatalf("ReadFiles() error = %v", err)
	}
	if len(got) != 0 {
		t.Errorf("ReadFiles() = %v, want empty slice", got)
	}
}

func TestStringList_ReadFiles_NoFile(t *testing.T) {
	sl := stringList("/non/existent/file.txt")
	_, err := sl.ReadFiles()
	if err == nil {
		t.Error("ReadFiles() expected error for non-existent file")
	}
}
