# Nova Toll showcase

The Vue 3 showcase lives in `site/` and is published through GitHub Pages at:

<https://alchemist-aloha.github.io/NovaToll/>

## Run locally

From the repository root:

```sh
npm ci --prefix site
npm run dev --prefix site
```

Open the local URL printed by Vite. To create the production bundle locally:

```sh
npm run build --prefix site
```

The generated static files are written to `site/dist/`.

## Deployment

`.github/workflows/showcase-pages.yml` builds and deploys the showcase on pushes
to `main` or `master` when `site/`, the showcase images/fonts, or the workflow
changes. It can also be started with **Actions → Deploy Vue showcase → Run
workflow**.

The repository’s Pages source must be set to **GitHub Actions** once in the
repository settings. The workflow uses the `github-pages` environment and
publishes the contents of `site/dist` as a single-page static site.
