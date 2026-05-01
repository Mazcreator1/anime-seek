import LegalPage from "../components/legalpage";

export default function PrivacyPage() {
  return (
    <LegalPage title="Privacy Policy">
      <p><strong>Effective Date:</strong> [02/24/2026]</p>

      <h3 style={{ marginTop: 18 }}>1. Information We Collect</h3>
      <p><strong>Account Information</strong></p>
      <ul>
        <li>Username</li>
        <li>Email address</li>
      </ul>

      <p><strong>User-Generated Content</strong></p>
      <ul>
        <li>Uploaded images/gifs (e.g., JPG, GIF)</li>
        <li>Posts</li>
        <li>Likes</li>
        <li>Follows</li>
      </ul>

      <h3 style={{ marginTop: 18 }}>2. Payments (Stripe)</h3>
      <p>
        If you purchase a subscription or paid feature, payments are processed by <strong>Stripe</strong>.
        We do not store full card details. We may store billing metadata such as your Stripe customer ID,
        subscription status, tier, and expiration timestamps.
      </p>
      <p style={{ opacity: 0.9 }}>
        Stripe Privacy Policy:{" "}
        <a href="https://stripe.com/privacy" target="_blank" rel="noreferrer">
          https://stripe.com/privacy
        </a>
      </p>

      <h3 style={{ marginTop: 18 }}>3. Third-Party Data</h3>
      <p>
        Anime metadata and images are retrieved from third-party APIs such as AniList. We do not host or
        redistribute anime episodes or previews; matching is performed using stored vectors only.
      </p>

      <h3 style={{ marginTop: 18 }}>4. Contact</h3>
      <p>
        Questions: <a href="mailto:devrecapz@gmail.com">devrecapz@gmail.com</a>
      </p>
    </LegalPage>
  );
}