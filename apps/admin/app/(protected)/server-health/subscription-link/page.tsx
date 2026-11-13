import type { Metadata } from "next";
import { SubscriptionLinkControl } from "@/components/subscription-link-control";
import { getSubscriptionLink } from "@/lib/subscription-link";

export const metadata: Metadata = {
  title: "Subscription links",
};

export default async function SubscriptionLinkPage() {
  const { choice, options } = await getSubscriptionLink();

  return (
    <>
      <section
        className="page-heading"
        aria-labelledby="subscription-link-title"
      >
        <h1 id="subscription-link-title">Subscription links</h1>
        <p>
          The link people make in the app for iPhone and iPad apps (Streisand,
          V2Box, Hiddify, FoXray) names an address those apps fetch it from.
          From Iran this server&apos;s own address and the CDN are often
          blocked; a relay server in Iran passes the link on to here.
        </p>
      </section>
      <section className="status-card" aria-labelledby="subscription-choice">
        <h2 id="subscription-choice">Address</h2>
        <SubscriptionLinkControl choice={choice} options={options} />
      </section>
    </>
  );
}
