import type { Metadata } from "next";
import { DnsRecordsView } from "@/components/dns-records";

export const metadata: Metadata = {
  title: "DNS records",
};

export default function DnsRecordsPage() {
  return (
    <>
      <section className="page-heading" aria-labelledby="dns-records-title">
        <h1 id="dns-records-title">DNS records</h1>
        <p>
          Every name this deployment uses, where it must point, and whether the
          public DNS already says so: the panel and the API, each server&apos;s
          own name, the CDN names and the DNS tunnels. Add any marked
          &ldquo;Fix&rdquo; at your DNS provider, then check again.
        </p>
      </section>
      <DnsRecordsView />
    </>
  );
}
