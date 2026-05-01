Widget _recentActivity(List<Activity> recent) {
  if (recent.isEmpty) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Recent Activity',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 12),
          Text('No recent activity yet.'),
        ],
      ),
    );
  }

  // return actual activity UI here
  return const SizedBox.shrink();
}
