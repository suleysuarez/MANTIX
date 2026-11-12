part of 'inventory_bloc.dart';

class InventoryState extends Equatable {
  const InventoryState({
    this.loading = false, this.saving = false, this.items = const [], this.options = const [],
    this.pageInfo, this.overview, this.page = 1, this.pageSize = 10, this.search = '',
    this.category, this.status, this.failure, this.createdItem, this.notice,
  });

  final bool loading;
  final bool saving;
  final List<InventoryItem> items;
  final List<InventoryOption> options;
  final PageInfo? pageInfo;
  final InventoryOverview? overview;
  final int page;
  final int pageSize;
  final String search;
  final String? category;
  final String? status;
  final Failure? failure;
  final InventoryItem? createdItem;
  final String? notice;

  int get total => pageInfo?.total ?? items.length;
  int get totalPages => pageInfo?.totalPages ?? 1;

  InventoryState copyWith({
    bool? loading, bool? saving, List<InventoryItem>? items, List<InventoryOption>? options,
    PageInfo? pageInfo, bool clearPageInfo = false, InventoryOverview? overview, int? page,
    int? pageSize, String? search, String? category, bool clearCategory = false,
    String? status, bool clearStatus = false, Failure? failure, bool clearFailure = false,
    InventoryItem? createdItem, bool clearCreated = false, String? notice,
  }) => InventoryState(
    loading: loading ?? this.loading, saving: saving ?? this.saving, items: items ?? this.items,
    options: options ?? this.options, pageInfo: clearPageInfo ? null : (pageInfo ?? this.pageInfo),
    overview: overview ?? this.overview, page: page ?? this.page, pageSize: pageSize ?? this.pageSize,
    search: search ?? this.search, category: clearCategory ? null : (category ?? this.category),
    status: clearStatus ? null : (status ?? this.status), failure: clearFailure ? null : (failure ?? this.failure),
    createdItem: clearCreated ? null : (createdItem ?? this.createdItem), notice: notice ?? this.notice,
  );

  @override
  List<Object?> get props => [loading, saving, items, options, pageInfo, overview, page, pageSize, search, category, status, failure, createdItem, notice];
}
