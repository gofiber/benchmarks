package benchmarks

import (
	"encoding/json"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/cors"
	recoverer "github.com/gofiber/fiber/v3/middleware/recover"
	"github.com/valyala/fasthttp"
)

type payload struct {
	Name   string `json:"name" query:"name"`
	ID     int    `json:"id" query:"id"`
	Active bool   `json:"active"`
}

var corsConfig = cors.Config{AllowOrigins: []string{"https://bench.invalid"}, AllowMethods: []string{"GET", "POST"}}

func app(routes func(*fiber.App), config ...fiber.Config) fasthttp.RequestHandler {
	a := fiber.New(config...)
	routes(a)
	return a.Handler()
}

func ok(c fiber.Ctx) error { return c.SendString("ok") }

func scenarios() []scenario {
	list := []scenario{
		{
			name: "fasthttp_only", method: "GET", uri: "/hello", wantStatus: 200, wantBody: "hello",
			handler: func(c *fasthttp.RequestCtx) { c.SetBodyString("hello") },
		},
		{
			name: "static", method: "GET", uri: "/hello", wantStatus: 200, wantBody: "hello",
			handler: app(func(a *fiber.App) {
				a.Get("/hello", func(c fiber.Ctx) error { return c.SendString("hello") })
			}),
		},
		{
			name: "parameter", method: "GET", uri: "/users/42", wantStatus: 200, wantBody: "42",
			handler: app(func(a *fiber.App) {
				a.Get("/users/:id", func(c fiber.Ctx) error { return c.SendString(c.Params("id")) })
			}),
		},
		{
			name: "wildcard", method: "GET", uri: "/files/a/b", wantStatus: 200, wantBody: "a/b",
			handler: app(func(a *fiber.App) {
				a.Get("/files/*", func(c fiber.Ctx) error { return c.SendString(c.Params("*")) })
			}),
		},
		{
			name: "query_lookup", method: "GET", uri: "/query?name=alice", wantStatus: 200, wantBody: "alice",
			handler: app(func(a *fiber.App) {
				a.Get("/query", func(c fiber.Ctx) error { return c.SendString(c.Query("name")) })
			}),
		},
		{
			name: "header_lookup", method: "GET", uri: "/header", wantStatus: 200, wantBody: "hello",
			headers: []header{{"X-Bench", "hello"}},
			handler: app(func(a *fiber.App) {
				a.Get("/header", func(c fiber.Ctx) error { return c.SendString(c.Get("X-Bench")) })
			}),
		},
		{
			name: "locals", method: "GET", uri: "/locals", wantStatus: 200, wantBody: "alice",
			handler: app(func(a *fiber.App) {
				a.Use(func(c fiber.Ctx) error {
					c.Locals("name", "alice")
					return c.Next()
				})
				a.Get("/locals", func(c fiber.Ctx) error {
					name, ok := c.Locals("name").(string)
					if !ok {
						return fiber.ErrInternalServerError
					}
					return c.SendString(name)
				})
			}),
		},
		{
			name: "query_bind", method: "GET", uri: "/bind?id=42&name=alice", wantStatus: 200, wantBody: "ok",
			handler: app(func(a *fiber.App) {
				a.Get("/bind", func(c fiber.Ctx) error {
					var p payload
					if err := c.Bind().Query(&p); err != nil {
						return err
					}
					if p != (payload{ID: 42, Name: "alice"}) {
						return fiber.ErrBadRequest
					}
					return ok(c)
				})
			}),
		},
		{
			name: "middleware_chain", method: "GET", uri: "/chain", wantStatus: 200, wantBody: "ok",
			handler: app(func(a *fiber.App) {
				for range 3 {
					a.Use(func(c fiber.Ctx) error { return c.Next() })
				}
				a.Get("/chain", ok)
			}),
		},
		{
			name: "cors_simple", method: "GET", uri: "/cors", wantStatus: 200, wantBody: "ok",
			headers:     []header{{"Origin", "https://bench.invalid"}},
			wantHeaders: []header{{"Access-Control-Allow-Origin", "https://bench.invalid"}},
			handler: app(func(a *fiber.App) {
				a.Use(cors.New(corsConfig))
				a.Get("/cors", ok)
			}),
		},
		{
			name: "cors_preflight", method: "OPTIONS", uri: "/cors", wantStatus: 204,
			headers: []header{{"Origin", "https://bench.invalid"}, {"Access-Control-Request-Method", "POST"}},
			wantHeaders: []header{
				{"Access-Control-Allow-Origin", "https://bench.invalid"},
				{"Access-Control-Allow-Methods", "GET, POST"},
			},
			handler: app(func(a *fiber.App) { a.Use(cors.New(corsConfig)) }),
		},
		{
			name: "recover_no_panic", method: "GET", uri: "/recover", wantStatus: 200, wantBody: "ok",
			handler: app(func(a *fiber.App) {
				a.Use(recoverer.New())
				a.Get("/recover", ok)
			}),
		},
		{
			name: "not_found_default", method: "GET", uri: "/missing", wantStatus: 404, wantBody: "Not Found",
			handler: app(func(a *fiber.App) { a.Get("/exists", ok) }),
		},
		{
			name: "not_found_custom", method: "GET", uri: "/missing", wantStatus: 404, wantBody: "not found",
			handler: app(func(a *fiber.App) { a.Get("/exists", ok) }, fiber.Config{
				ErrorHandler: func(c fiber.Ctx, _ error) error { return c.Status(404).SendString("not found") },
			}),
		},
	}

	// the suffix is the length of the JSON name field
	for _, v := range []struct{ suffix, name string }{
		{"", "alice"},
		{"_1024", strings.Repeat("x", 1024)},
		{"_16384", strings.Repeat("x", 16384)},
	} {
		want := payload{ID: 42, Name: v.name, Active: true}
		body, err := json.Marshal(want)
		if err != nil {
			panic(err)
		}
		list = append(list,
			scenario{
				name: "json_response" + v.suffix, method: "GET", uri: "/json", wantStatus: 200, wantBody: string(body),
				handler: app(func(a *fiber.App) {
					a.Get("/json", func(c fiber.Ctx) error { return c.JSON(want) })
				}),
			},
			scenario{
				name: "json_bind" + v.suffix, method: "POST", uri: "/bind", body: string(body), wantStatus: 200, wantBody: "ok",
				headers: []header{{"Content-Type", "application/json"}},
				handler: app(func(a *fiber.App) {
					a.Post("/bind", func(c fiber.Ctx) error {
						var p payload
						if err := c.Bind().Body(&p); err != nil {
							return err
						}
						if p != want {
							return fiber.ErrBadRequest
						}
						return ok(c)
					})
				}),
			},
		)
	}

	for _, n := range []int{100, 1000} {
		list = append(list, scenario{
			name: "static_routes_" + strconv.Itoa(n), method: "GET", uri: "/routes/" + strconv.Itoa(n-1),
			wantStatus: 200, wantBody: "ok",
			handler: app(func(a *fiber.App) {
				for i := range n {
					a.Get("/routes/"+strconv.Itoa(i), ok)
				}
			}),
		})
	}
	return list
}
