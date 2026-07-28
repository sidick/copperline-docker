# Examples

Ready-to-adapt `docker-compose.yml` recipes, one directory per use case.
Run any of them with `docker compose up` from inside its directory (add
your own disk/ROM files first where noted).

| Example | What it shows |
| --- | --- |
| [`kiosk/`](kiosk/) | One demo/game, preloaded and autobooted — visitors land in the running software |
| [`disk-shelf/`](disk-shelf/) | A mounted disk library, browsable from the page's list dropdowns |
| [`bbs-terminal/`](bbs-terminal/) | Boot straight into a telnet BBS over the emulated serial port |
| [`reskin/`](reskin/) | Retitle and retheme the stock page without touching HTML |
| [`custom-shell/`](custom-shell/) | Replace the page entirely — the minimal working shell contract |
| [`private/`](private/) | Keep a deployment (and the files it serves) off the open internet |

All of these compose the same three mechanisms, documented in the main
README: the `/files` volume, `COPPERLINE_*` environment variables (or a
mounted `copperline.json`), and mounts over `theme.css` / `index.html` /
the nginx config.
