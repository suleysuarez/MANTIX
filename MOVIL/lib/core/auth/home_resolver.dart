/// Pantalla de inicio según los permisos efectivos (docs/flutter-plan.md).
enum HomeDestination {
  globalDashboard('/inicio/dashboard-global'),
  assignedInbox('/inicio/bandeja'),
  myRequests('/inicio/solicitudes'),
  reports('/inicio/reportes'),
  ownDashboard('/inicio/dashboard'),
  profile('/perfil');

  const HomeDestination(this.path);
  final String path;
}

/// Función pura: el primer criterio que coincide gana; si ninguno, Perfil.
HomeDestination resolveHome(Set<String> permissions) {
  bool has(String code) => permissions.contains(code);

  if (has('dashboard:ver_todos') && has('tickets:ver_todos')) return HomeDestination.globalDashboard;
  if (has('tickets:ver_asignados')) return HomeDestination.assignedInbox;
  if (has('solicitudes:ver')) return HomeDestination.myRequests;
  if (has('reportes:ver')) return HomeDestination.reports;
  if (has('dashboard:ver')) return HomeDestination.ownDashboard;
  return HomeDestination.profile;
}
