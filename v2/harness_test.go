package benchmarks

import (
	"bufio"
	"errors"
	"io"
	"net/http"
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
			var c fasthttp.RequestCtx
			prepare(&c, s)
			s.handler(&c)
			verify(b, &c, s)

			b.ReportAllocs()
			for b.Loop() {
				prepare(&c, s)
				s.handler(&c)
			}
			verify(b, &c, s)
		})
	}
}

func prepare(c *fasthttp.RequestCtx, s *scenario) {
	c.Request.Reset()
	c.Response.Reset()
	c.ResetUserValues()
	c.Request.Header.SetMethod(s.method)
	c.Request.SetRequestURI(s.uri)
	for _, h := range s.headers {
		c.Request.Header.Set(h.name, h.value)
	}
	if s.body != "" {
		c.Request.SetBodyString(s.body)
	}
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
