build-w:
	GOOS=windows GOARCH=386 go build -o ./build/recepient/recepient.exe ./cmd/recepient/recepient.go
	GOOS=windows GOARCH=386 go build -o ./build/sender/sender.exe ./cmd/sender/sender.go
build-l:
	GOOS=linux GOARCH=amd64 go build -o ./build/recepient/recepient ./cmd/recepient/recepient.go
	GOOS=linux GOARCH=amd64 go build -o ./build/sender/sender ./cmd/sender/sender.go