import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/equipment/custodian_search_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../home/mantix_drawer.dart';

/// Lo que devuelve el selector: un usuario elegido o «sin responsable».
class CustodianChoice {
  const CustodianChoice.picked(CustodianCandidate this.candidate) : cleared = false;
  const CustodianChoice.cleared() : candidate = null, cleared = true;

  final CustodianCandidate? candidate;
  final bool cleared;
}

/// Hoja inferior para buscar a quien quedará a cargo del equipo (por nombre o correo).
/// Devuelve `null` si se cierra sin elegir.
Future<CustodianChoice?> showCustodianPicker(BuildContext context, {CustodianCandidate? selected}) {
  final repository = context.read<EquipmentRepository>();
  return showModalBottomSheet<CustodianChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => BlocProvider(
      create: (_) => CustodianSearchBloc(repository: repository)..add(const CustodianSearched('')),
      child: _CustodianSheet(selected: selected),
    ),
  );
}

class _CustodianSheet extends StatefulWidget {
  const _CustodianSheet({this.selected});

  final CustodianCandidate? selected;

  @override
  State<_CustodianSheet> createState() => _CustodianSheetState();
}

class _CustodianSheetState extends State<_CustodianSheet> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) context.read<CustodianSearchBloc>().add(CustodianSearched(text));
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Responsable del equipo', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                maxLength: 100,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: const InputDecoration(hintText: 'Buscar por nombre o correo…', counterText: '', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            if (widget.selected != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(const CustodianChoice.cleared()),
                  icon: const Icon(Icons.person_off_outlined, size: 18),
                  label: const Text('Quitar responsable'),
                ),
              ),
            Flexible(child: _Results(selected: widget.selected)),
          ]),
        ),
      );
}

class _Results extends StatelessWidget {
  const _Results({this.selected});

  final CustodianCandidate? selected;

  @override
  Widget build(BuildContext context) => BlocBuilder<CustodianSearchBloc, CustodianSearchState>(
        builder: (context, state) {
          if (state.status == CustodianSearchStatus.failure) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(state.failure?.message ?? 'No pudimos buscar usuarios.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate)),
                TextButton(onPressed: () => context.read<CustodianSearchBloc>().add(CustodianSearched(state.query)), child: const Text('Reintentar')),
              ]),
            );
          }
          final waiting = state.status == CustodianSearchStatus.loading || state.status == CustodianSearchStatus.idle;
          if (state.results.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: waiting
                    ? const CircularProgressIndicator(semanticsLabel: 'Buscando usuarios')
                    : const Text('No encontramos usuarios con ese nombre o correo.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.slate)),
              ),
            );
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (waiting) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.results.length,
                itemBuilder: (context, index) {
                  final candidate = state.results[index];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: AppColors.sky, child: Text(initialsOf(candidate.fullName), style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w800))),
                    title: Text(candidate.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(candidate.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: selected?.id == candidate.id ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)) : null,
                    onTap: () => Navigator.of(context).pop(CustodianChoice.picked(candidate)),
                  );
                },
              ),
            ),
          ]);
        },
      );
}
