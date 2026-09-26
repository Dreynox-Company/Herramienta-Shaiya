import 'package:flutter/material.dart';
import '../data/library.dart';

enum ItemsRecoveryAction { resources, spk, reference }

/// A readable payload and a proven path are different facts. This panel never
/// fabricates DBItemData or imports tables silently from a different library.
class ItemsSourceRecovery extends StatelessWidget {
  final Library library;
  final String error;
  final VoidCallback onRetry;
  final ValueChanged<ItemsRecoveryAction>? onRecovery;
  const ItemsSourceRecovery({
    super.key,
    required this.library,
    required this.error,
    required this.onRetry,
    this.onRecovery,
  });

  @override
  Widget build(BuildContext context) {
    final source = library.spk;
    final confirmed = source == null
        ? 0
        : source.index.resources
              .where((r) => source.names.isConfirmed(r.entryId))
              .length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.account_tree_outlined, size: 30),
              const SizedBox(height: 12),
              Text(
                'El catálogo de Ítems necesita su tabla real',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text(
                source == null
                    ? 'Esta biblioteca no permite abrir BinarySData/DBItemData.SData. '
                          'Comprueba la raíz DATA y el diagnóstico. Los demás recursos siguen disponibles.'
                    : 'El SPK está conectado, pero la tabla de Ítems todavía no está disponible '
                          'en una ruta confirmada y legible. Esto puede deberse a su identificación, '
                          'al perfil de lectura o a sus fragmentos; el error no demuestra por sí solo '
                          'que todos los recursos estén cifrados.',
              ),
              if (source != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${source.index.resources.length} registros indexados · $confirmed rutas confirmadas',
                ),
                Text(
                  'Lectura simple: ${source.canReadSimpleResources ? 'habilitada' : 'pendiente'} · '
                  'fragmentados: ${source.canReadFragmentedResources ? 'habilitados' : 'pendientes'}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Una carpeta DATA original puede servir para confirmar rutas por '
                  'contenido completo. No se sustituyen los bytes del SPK ni se aceptan '
                  'nombres deducidos solo por tamaño. Un recurso que falte o sea distinto '
                  'en esa referencia puede seguir sin resolverse.',
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onRecovery != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('items-open-resources'),
                      onPressed: () =>
                          onRecovery!(ItemsRecoveryAction.resources),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Ver recursos'),
                    ),
                  if (source != null && onRecovery != null) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('items-open-spk'),
                      onPressed: () => onRecovery!(ItemsRecoveryAction.spk),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Revisar perfil SPK'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('items-confirm-paths'),
                      onPressed: source.canReadSimpleResources
                          ? () => onRecovery!(ItemsRecoveryAction.reference)
                          : null,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Confirmar rutas'),
                    ),
                  ],
                  TextButton.icon(
                    key: const ValueKey('items-retry-load'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                title: const Text('Diagnóstico técnico'),
                tilePadding: EdgeInsets.zero,
                children: [SelectableText(error)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
