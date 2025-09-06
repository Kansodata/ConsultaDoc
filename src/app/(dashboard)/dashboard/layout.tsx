export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className="grid gap-6">{children}</div>;
}
