// pages/credits.js
import LegalPage from "../components/legalpage";

export default function CreditsPage() {
  return (
    <LegalPage title="Credits">
      <p>This project uses third-party services and data sources. Credits:</p>
      <ul>
        <li>
          <strong>AniList</strong> — anime metadata and images.
        </li>
        <li>
          <strong>trace.moe (Soruly)</strong> — open-source inspiration for scene matching workflows (self-hosted).
        </li>
      </ul>
      <p style={{ opacity: 0.9 }}>
        Anime Seek is not affiliated with or endorsed by AniList or trace.moe.
      </p>
    </LegalPage>
  );
}