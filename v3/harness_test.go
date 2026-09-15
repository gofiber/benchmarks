package benchmarks

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/valyala/fasthttp"
)

type header struct{ name, value string }

type scenario struct {
	handler                           fasthttp.RequestHandler
	name, method, uri, body, wantBody string
	headers, wantHeaders              []header
	wantStatus                        int
}

func BenchmarkRequest(b *testing.B) {
	list := scenarios()
	for i := range list {
		s := &list[i]
		b.Run(s.name, func(b *testing.B) {
			var (
				c   fasthttp.RequestCtx
				src bytes.Reader
			)
			br := bufio.NewReader(&src)
			raw := rawRequest(s)
			if err := prepare(&c, br, &src, raw); err != nil {
				b.Fatal(err)
			}
			s.handler(&c)
			verify(b, &c, s)

			b.ReportAllocs()
			for b.Loop() {
				if err := prepare(&c, br, &src, raw); err != nil {
					b.Fatal(err)
				}
				s.handler(&c)
			}
			verify(b, &c, s)
		})
	}
}

func rawRequest(s *scenario) []byte {
	lines := []string{s.method + " " + s.uri + " HTTP/1.1", "Host: bench.invalid"}
	for _, h := range s.headers {
		lines = append(lines, h.name+": "+h.value)
	}
	if s.body != "" {
		lines = append(lines, "Content-Length: "+strconv.Itoa(len(s.body)))
	}
	return []byte(strings.Join(lines, "\r\n") + "\r\n\r\n" + s.body)
}

// parsing like a server keeps setter-only costs, such as fasthttp's CRLF sanitizing, out of the timing
func prepare(c *fasthttp.RequestCtx, br *bufio.Reader, src *bytes.Reader, raw []byte) error {
	c.Request.Reset()
	c.Response.Reset()
	c.ResetUserValues()
	src.Reset(raw)
	br.Reset(src)
	return c.Request.Read(br)
}

// verify reads the serialized response, so a body buffer fasthttp never sends (e.g. on 204) doesn't count.
func verify(tb testing.TB, c *fasthttp.RequestCtx, s *scenario) {
	tb.Helper()
	r := bufio.NewReader(strings.NewReader(c.Response.String()))
	res, err := http.ReadResponse(r, &http.Request{Method: s.method})
	if err != nil {
		tb.Fatal(err)
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		tb.Fatal(err)
	}
	if _, err := r.Peek(1); !errors.Is(err, io.EOF) {
		tb.Fatal("unexpected bytes after the response")
	}
	if res.StatusCode != s.wantStatus || string(body) != s.wantBody {
		tb.Fatalf("got %d %q, want %d %q", res.StatusCode, body, s.wantStatus, s.wantBody)
	}
	for _, h := range s.wantHeaders {
		if got := res.Header.Get(h.name); got != h.value {
			tb.Fatalf("%s: got %q, want %q", h.name, got, h.value)
		}
	}
}
