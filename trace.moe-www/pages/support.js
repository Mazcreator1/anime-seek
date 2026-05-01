import LegalPage from "../components/legalpage";

export default function SupportPage() {
  return (
    <LegalPage title="Contact / Support">
      <p>
        Email: <a href="mailto:devrecapz@gmail.com">devrecapz@gmail.com</a>
      </p>
      <p style={{ opacity: 0.9 }}>
        Include steps to reproduce, screenshots, and your browser/device details.
      </p>
    </LegalPage>
  );
}