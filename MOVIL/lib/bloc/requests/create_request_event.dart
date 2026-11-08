part of 'create_request_bloc.dart';

sealed class CreateRequestEvent {
  const CreateRequestEvent();
}

class CreateRequestSubmitted extends CreateRequestEvent {
  const CreateRequestSubmitted(this.request);

  final NewRequest request;
}
