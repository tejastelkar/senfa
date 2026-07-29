# Shopify Deployment Guide

This guide explains how to properly push theme changes to the Shopify store using the Shopify CLI. 

## Important Store Information
* **Public Domain:** `senfa.shop`
* **Underlying Shopify Domain:** `0pjcz9-vg.myshopify.com`
* **Live Theme:** `Dawn` (ID: `137869197521`)

Because the store uses a generated underlying domain (`0pjcz9-vg.myshopify.com`), all CLI commands **must** specify this domain using the `--store` flag.

---

## 1. Authentication

There is no `--store` flag on `shopify auth login` in current CLI versions (4.x). Auth happens implicitly on the first `theme`/`app` command that targets a store — just pass `--store` on that command and the CLI will prompt you to log in if needed:

```bash
shopify theme list --store 0pjcz9-vg.myshopify.com
```
*Note: A device-code link will be printed and opened in your browser. Approve it there, then the CLI logs in and the command proceeds. You only need to do this once per session or if your token expires.*

To switch accounts/stores (e.g. logging out of a different store you were previously authenticated to):

```bash
shopify auth logout
```

---

## 2. Listing Themes

To see all available themes (live and unpublished) and their IDs:

```bash
shopify theme list --store 0pjcz9-vg.myshopify.com
```

---

## 3. Pushing Changes

### Pushing to the Live Theme (Production)
To push changes directly to the live `Dawn` theme, use the following command. The `--allow-live` flag is required so it doesn't prompt for confirmation:

```bash
shopify theme push --theme 137869197521 --store 0pjcz9-vg.myshopify.com --allow-live
```

### Pushing to an Unpublished Theme
If you want to push to an unpublished theme (e.g., for testing before pushing live), replace the theme ID with the unpublished theme's ID from the `theme list` command:

```bash
shopify theme push --theme <THEME_ID> --store 0pjcz9-vg.myshopify.com
```

---

## Alternative: GitHub Integration
Since this repository is connected to GitHub (`https://github.com/tejastelkar/senfa.git`), you can also deploy by:
1. Pushing your changes to the `main` branch on GitHub.
2. The Shopify admin will automatically pull the latest changes if you have connected the GitHub repository via **Online Store > Themes > Add theme > Connect from GitHub**.
