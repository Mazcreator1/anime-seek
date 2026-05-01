// components/legalpage.js
import Head from "next/head";
import Layout from "./layout";

const SURFACE = "#22242A";
const TEXT = "#FFFFFF";

export default function legalpage({ title, children }) {
  return (
    <Layout title={title}>
      <Head>
        <meta name="theme-color" content={SURFACE} />
      </Head>

      <div style={{ background: SURFACE, color: TEXT }}>
        <div style={{ maxWidth: 980, margin: "0 auto", padding: "28px 16px 80px" }}>
          <h1 style={{ margin: "0 0 16px", fontSize: 28 }}>{title}</h1>

          <div
            style={{
              border: "1px solid #3A3F47",
              borderRadius: 16,
              padding: 18,
              lineHeight: 1.6,
              background: "#1E2026",
            }}
          >
            {children}
          </div>

          <div style={{ marginTop: 18, opacity: 0.85 }}>
            <a href="/" style={{ color: TEXT, textDecoration: "underline" }}>
              ← Back to Search
            </a>
          </div>
        </div>
      </div>

      <style jsx global>{`
        :root { color-scheme: dark; }
        html, body, #__next { background: #22242A; }
        body { color: #FFFFFF; -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }
        a { color: #FFFFFF; }
      `}</style>
    </Layout>
  );
}