part of 'custodian_search_bloc.dart';

sealed class CustodianSearchEvent {
  const CustodianSearchEvent();
}

/// Busca por nombre o correo; un texto vacío trae los primeros usuarios.
class CustodianSearched extends CustodianSearchEvent {
  const CustodianSearched(this.text);

  final String text;
}
