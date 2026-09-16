<p align="center">
  <img height="125" alt="Fiber Benchmarks" src="https://raw.githubusercontent.com/gofiber/benchmarks/main/.github/logo-dark.svg#gh-dark-mode-only" />
  <img height="125" alt="Fiber Benchmarks" src="https://raw.githubusercontent.com/gofiber/benchmarks/main/.github/logo.svg#gh-light-mode-only" />
</p>

In-process request benchmarks for Fiber v2 and v3: the latest v2 release against v3.0.0, the latest v3 release and v3 `main`. Each scenario is written against the version's own API, and each version builds with the dependencies it ships with.

**Results:** https://gofiber.github.io/benchmarks/

| Path | Content |
| --- | --- |
| `v2/`, `v3/` | One Go module per major version, the Fiber pin in `go.mod` is bumped by Dependabot. `compare.sh` also builds the v3 scenarios against v3.0.0 and `main` |
| `*/harness_test.go` | Request parsing, timing and response checks, identical in both modules |
| `*/scenarios_test.go` | The scenarios in each version's API |
| `compare.sh` | Paired runs of all versions and the `benchstat` comparison |
| `paired.py` | Median time ratio of each version against v2 per scenario with a sign-test interval |
| `site/` | The results page and the script that publishes a run to it |

## Running

```sh
make compare                        # COUNT=10 BENCHTIME=500ms
COUNT=20 BENCHTIME=1s make compare
```

It needs Go and python3. A run whose median paired interval is ±10% or wider after `COUNT` rounds gets `COUNT` more.
`LAYOUTS=5` builds every version that many times with different function layouts, and the rounds cycle through them.

CI runs the comparison on every push and pull request. The paired and benchstat tables are in the job summary, the raw results are attached as an artifact.

## Reading the results

- `sec/op` covers parsing the raw request and the handler, as a server runs them for every request. App construction, serializing the response and the network are not included, so it is not end-to-end latency.
- Where the linker puts a function changes a cheap scenario by tens of nanoseconds, more than most version differences. Every version is therefore built in `LAYOUTS` layouts, the default one and random ones, and each round moves to the next. The interval covers that spread.
- Each round runs all versions of a scenario back to back, rotating which goes first. `paired.py` reports the median of the per-round ratios against v2 with a sign-test interval, so load on the CI host that hits both halves of a pair cancels out. `benchstat` still gives the absolute numbers per version and the memory and allocation changes.
- v3.0.0 and `main` are resolved on every run, `main` at its latest commit. The published metadata names the exact versions.
- Every scenario checks status, body and required headers before and after timing.
- `fasthttp_floor` runs no Fiber code and shows what the fasthttp version alone changes.
- `not_found_default` uses each version's default body, `not_found_custom` the same custom body in both.

The scenarios are based on the comparison by @fzlzjerry in [gofiber/fiber#4669](https://github.com/gofiber/fiber/pull/4669).

<!-- skip-docs -->
## ☕ Supporters

Fiber is an open-source project that runs on donations to pay the bills, e.g., our domain name, hosting, and serverless infrastructure. If you want to support Fiber, please become a [GitHub Sponsor](https://github.com/sponsors/gofiber).

<p align="center">
  <a href="https://www.coderabbit.ai/?utm_source=gofiber&utm_medium=sponsor&utm_content=readme">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://www.coderabbit.ai/images/logo-dark.svg">
      <img width="280" height="52" alt="CodeRabbit" src="https://www.coderabbit.ai/images/logo-orange.svg">
    </picture>
  </a>
</p>
<p align="center">
  <a href="https://blacksmith.sh/?utm_source=gofiber&utm_medium=sponsor&utm_content=readme">
    <img width="280" height="96" alt="Blacksmith" src="https://raw.githubusercontent.com/gofiber/.github/main/assets/sponsors/blacksmith.png">
  </a>
</p>
<p align="center">
  <sub><b>Tool Sponsors</b> - supporting Fiber with free IDE licenses and AI credits</sub>
</p>
<p align="center">
  <a href="https://www.jetbrains.com/?from=gofiber" title="JetBrains - IDE licenses"><img width="36" height="36" alt="JetBrains" src="https://github.com/JetBrains.png?size=72"></a>
  &nbsp;
  <a href="https://openai.com/?utm_source=gofiber&utm_medium=sponsor&utm_content=readme" title="OpenAI - AI credits"><img width="36" height="36" alt="OpenAI" src="https://github.com/openai.png?size=72"></a>
  &nbsp;
  <a href="https://www.anthropic.com/?utm_source=gofiber&utm_medium=sponsor&utm_content=readme" title="Anthropic - AI credits"><img width="36" height="36" alt="Anthropic" src="https://github.com/anthropics.png?size=72"></a>
</p>

<!-- sponsors -->

### 📅 Monthly Sponsors

<table>
<tr><td valign="top"><strong>🔥 Fiber Guardian</strong></td><td><a href="https://www.coderabbit.ai/?utm_source=cr_org&amp;utm_medium=github" title="@coderabbitai"><img src="https://github.com/coderabbitai.png" width="50" alt="@coderabbitai" /></a></td></tr>
<tr><td valign="top"><strong>☕ Fiber Supporter</strong></td><td><a href="https://ndole.studio" title="@NdoleStudio"><img src="https://github.com/NdoleStudio.png" width="34" alt="@NdoleStudio" /></a></td></tr>
<tr><td valign="top"><strong>🪴 Fiber Friend</strong></td><td><a href="https://github.com/simonheisstpeter" title="@simonheisstpeter"><img src="https://github.com/simonheisstpeter.png" width="32" alt="@simonheisstpeter" /></a></td></tr>
</table>

### 🎁 One-time Sponsors

<table>
<tr><td valign="top"><strong>🚀 Fiber Hero</strong></td><td><a href="https://www.thanks.dev" title="@thnxdev"><img src="https://github.com/thnxdev.png" width="40" alt="@thnxdev" /></a></td></tr>
<tr><td valign="top"><strong>🪴 Fiber Friend</strong></td><td><a href="https://github.com/Gl1tchedPixzl" title="@Gl1tchedPixzl"><img src="https://github.com/Gl1tchedPixzl.png" width="26" alt="@Gl1tchedPixzl" /></a></td></tr>
</table>
<!-- sponsors -->
<!-- skip-docs -->

## License

MIT licensed. See the LICENSE file for details.
