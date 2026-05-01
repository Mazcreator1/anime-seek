import Head from "next/head";
import Link from "next/link";
import {
  footer,
  container,
  section,
  sectionHeader,
  sectionItem,
} from "./footer.module.css";

export default function Layout({ children, title }) {
  const pageTitle = title ? `${title} - anime-seek` : "anime-seek";

  return (
    <>
      <Head>
        <meta
          name="viewport"
          content="width=device-width, initial-scale=1.0, viewport-fit=cover"
        />
        <meta name="theme-color" content="#f9f9fb" />
        <meta
          name="description"
          content="Search Anime by ScreenShot. Lookup the exact moment and the episode."
        />
        <meta
          name="keywords"
          content="Anime Scene Search, Search by image, Anime Image Search, アニメのキャプ画像"
        />
        <title>{pageTitle}</title>
        <link rel="icon" type="image/png" href="/favicon.png" />
        <link rel="icon" type="image/png" href="/favicon128.png" sizes="128x128" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <link rel="manifest" href="/manifest.json" />
      </Head>

      <div
        style={{
          minHeight: "100vh",
          display: "flex",
          flexDirection: "column",
        }}
      >
        <main style={{ flex: 1 }}>{children}</main>

        <footer className={footer}>
          <div className={container}>
            <div className={section}>
              <div className={sectionHeader}>
                <Link href="/">anime-seek.com</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/about">About</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/credits">Credits</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/faq">FAQ</Link>
              </div>
            </div>

            <div className={section}>
              <div className={sectionHeader}>Legal</div>
              <div className={sectionItem}>
                <Link href="/privacy">Privacy</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/terms">Terms</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/csae-policy">CSAE Policy</Link>
              </div>
              <div className={sectionItem}>
                <Link href="/support">Support</Link>
              </div>
            </div>

            <div className={section}>
              <div className={sectionHeader}>Community</div>
              <div className={sectionItem}>
                <a
                  href="https://discord.gg/RhVnBDUC94"
                  target="_blank"
                  rel="noreferrer"
                >
                  Discord
                </a>
              </div>
            </div>
          </div>
        </footer>
      </div>

      <script src="/js/pwa.js" defer></script>
    </>
  );
}