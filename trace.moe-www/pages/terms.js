import LegalPage from "../components/legalpage";

export default function TermsPage() {
  return (
    <LegalPage title="Terms of Use">
      <p><strong>Effective Date:</strong> [02/24/2026]</p>

      <h3 style={{ marginTop: 18 }}>1. Accounts</h3>
      <ul>
        <li>You are responsible for your account and keeping credentials secure.</li>
        <li>You agree to provide accurate information.</li>
      </ul>

      <h3 style={{ marginTop: 18 }}>2. Acceptable Use</h3>
      <ul>
        <li>No illegal content or infringement of others’ rights.</li>
        <li>No harassment, abuse, or impersonation.</li>
        <li>No attempts to disrupt or overload the service.</li>
      </ul>

      <h3 style={{ marginTop: 18 }}>3. Content & Data</h3>
      <ul>
        <li>Anime Seek does not host or distribute full episodes or previews.</li>
        <li>Matching is performed using stored vectors only.</li>
        <li>Metadata and images are provided by third-party sources (e.g., AniList).</li>
      </ul>

      <h3 style={{ marginTop: 18 }}>4. Subscriptions (Stripe)</h3>
      <ul>
        <li>Paid features may require a subscription.</li>
        <li>Payments are processed by Stripe (we do not store card details).</li>
        <li>Subscriptions may renew unless canceled.</li>
      </ul>

      <h3 style={{ marginTop: 18 }}>5. Termination</h3>
      <p>
        We may suspend or terminate accounts that violate these Terms or harm the platform.
      </p>

      <h3 style={{ marginTop: 18 }}>6. Support</h3>
      <p>
        Support: <a href="mailto:devrecapz@gmail.com">devrecapz@gmail.com</a>
      </p>
    </LegalPage>
  );
}