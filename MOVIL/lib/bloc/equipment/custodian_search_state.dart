part of 'custodian_search_bloc.dart';

enum CustodianSearchStatus { idle, loading, success, failure }

class CustodianSearchState extends Equatable {
  const CustodianSearchState({this.status = CustodianSearchStatus.idle, this.query = '', this.results = const [], this.failure});

  final CustodianSearchStatus status;
  final String query;
  final List<CustodianCandidate> results;
  final Failure? failure;

  @override
  List<Object?> get props => [status, query, results, failure];
}
