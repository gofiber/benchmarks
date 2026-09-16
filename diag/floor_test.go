package floor

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"net"
	"testing"
	"time"

	"github.com/valyala/fasthttp"
)

var raw = []byte("GET /hello HTTP/1.1\r\nHost: bench.invalid\r\n\r\n")

// the benchmark harness reduced to fasthttp: reset, parse, and a handler that only sets a body
func BenchmarkRequest(b *testing.B) {
	b.Run("fasthttp_floor", func(b *testing.B) {
		var (
			c   fasthttp.RequestCtx
			src bytes.Reader
		)
		br := bufio.NewReader(&src)
		b.ReportAllocs()
		for b.Loop() {
			c.Request.Reset()
			c.Response.Reset()
			c.ResetUserValues()
			src.Reset(raw)
			br.Reset(&src)
			if err := c.Request.Read(br); err != nil {
				b.Fatal(err)
			}
			c.SetBodyString("hello")
		}
	})

	// the server path: parse, handler and response write on one keep-alive connection
	b.Run("serve_conn", func(b *testing.B) {
		served := 0
		s := &fasthttp.Server{Handler: func(c *fasthttp.RequestCtx) {
			served++
			c.SetBodyString("hello")
		}}
		conn := &pipeline{left: b.N}
		b.ReportAllocs()
		b.ResetTimer()
		err := s.ServeConn(conn)
		b.StopTimer()
		if served != b.N {
			b.Fatalf("served %d of %d (err %v)", served, b.N, err)
		}
	})
}

type pipeline struct {
	off, left int
}

func (p *pipeline) Read(b []byte) (int, error) {
	n := 0
	for n < len(b) && p.left > 0 {
		k := copy(b[n:], raw[p.off:])
		n += k
		p.off += k
		if p.off == len(raw) {
			p.off = 0
			p.left--
		}
	}
	if n == 0 {
		return 0, io.EOF
	}
	return n, nil
}

func (p *pipeline) Write(b []byte) (int, error)      { return len(b), nil }
func (p *pipeline) Close() error                     { return nil }
func (p *pipeline) LocalAddr() net.Addr              { return addr }
func (p *pipeline) RemoteAddr() net.Addr             { return addr }
func (p *pipeline) SetDeadline(time.Time) error      { return nil }
func (p *pipeline) SetReadDeadline(time.Time) error  { return nil }
func (p *pipeline) SetWriteDeadline(time.Time) error { return nil }

var addr = &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 8080}

var _ = errors.Is
