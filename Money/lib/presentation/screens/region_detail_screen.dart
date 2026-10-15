import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class RegionDetailScreen extends StatefulWidget {
  final int? regionId;
  final bool showAppBar;
  final bool embedded;
  final bool showEmbeddedHeader;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final VoidCallback? onCreated;

  const RegionDetailScreen({
    super.key,
    this.regionId,
    this.showAppBar = true,
    this.embedded = false,
    this.showEmbeddedHeader = true,
    this.onBack,
    this.onSaved,
    this.onCreated,
  });

  @override
  State<RegionDetailScreen> createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  final RegionService _regionService = RegionService();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _responsibleController = TextEditingController();
  final TextEditingController _parentController = TextEditingController();
  final TextEditingController _loanMessageController = TextEditingController();
  final TextEditingController _refinancedMessageController =
      TextEditingController();
  final TextEditingController _collectionMessageController =
      TextEditingController();
  final TextEditingController _collectionLinkController =
      TextEditingController();
  final TextEditingController _overdueMessageController =
      TextEditingController();

  AppRegionDetail? _region;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  bool _editing = false;
  bool _clientOwnerRequired = false;
  String? _errorMessage;

  bool get _isNew => widget.regionId == null;
  bool get _canEdit => AuthService().currentSession?.canManageRegions == true;

  bool get _fieldsEnabled => _canEdit && (_isNew || _editing);

  @override
  void initState() {
    super.initState();
    _editing = _isNew;
    if (_isNew) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _responsibleController.dispose();
    _parentController.dispose();
    _loanMessageController.dispose();
    _refinancedMessageController.dispose();
    _collectionMessageController.dispose();
    _collectionLinkController.dispose();
    _overdueMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = _isNew ? 'Nova região' : 'Detalhes da região';
    final Widget body = _buildBody();
    final Widget? actionBar = _loading || _errorMessage != null
        ? null
        : _RegionActionBar(
            canEdit: _canEdit,
            isNew: _isNew,
            editing: _editing,
            saving: _saving,
            onEdit: _saving || _deleting ? null : _startEditing,
            onSave: _saving || _deleting ? null : _save,
            onCancel: _saving || _deleting ? null : _goBack,
          );

    if (widget.embedded) {
      return ColoredBox(
        color: context.colors.background,
        child: Column(
          children: [
            Expanded(child: body),
            ?actionBar,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: title,
              leading: IconButton(
                tooltip: 'Voltar',
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            )
          : null,
      body: body,
      bottomNavigationBar: actionBar,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null) {
      return _RegionDetailMessage(message: _errorMessage!, onRetry: _load);
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          if (!widget.embedded || widget.showEmbeddedHeader)
            _RegionDetailHeader(
              description: _descriptionController.text,
              regionId: widget.regionId,
              canEdit: _canEdit,
              editing: _editing,
              deleting: _deleting,
              onDelete: _saving || _deleting || _isNew ? null : _confirmDelete,
            ),
          Material(
            color: context.colors.surface,
            child: TabBar(
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              indicatorColor: context.colors.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(height: 41, text: 'Identificação'),
                Tab(height: 41, text: 'Mensagens'),
                Tab(height: 41, text: 'Ajustes'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildIdentificationTab(),
                _buildMessagesTab(),
                _buildAdjustmentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentificationTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _RegionSectionCard(
              icon: Icons.location_on_outlined,
              title: 'Dados da região',
              subtitle: 'Identificação e responsáveis pela operação.',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool twoColumns = constraints.maxWidth >= 680;
                  return _RegionFieldGrid(
                    twoColumns: twoColumns,
                    children: [
                      if (!_isNew)
                        _RegionStaticField(
                          value: '${widget.regionId}',
                          label: 'ID da região',
                          icon: Icons.tag_rounded,
                        ),
                      _RegionTextField(
                        controller: _descriptionController,
                        label: 'Descrição',
                        icon: Icons.business_outlined,
                        enabled: _fieldsEnabled,
                        onChanged: (_) => setState(() {}),
                      ),
                      _RegionTextField(
                        controller: _responsibleController,
                        label: 'Responsável(s)',
                        icon: Icons.groups_2_outlined,
                        enabled: _fieldsEnabled,
                      ),
                      _RegionTextField(
                        controller: _parentController,
                        label: 'Empresa ou região pai',
                        icon: Icons.account_tree_outlined,
                        enabled: _fieldsEnabled,
                      ),
                      if (!_isNew)
                        _RegionStaticField(
                          value: _formatDateTime(_region?.createdAt),
                          label: 'Data de criação',
                          icon: Icons.event_available_outlined,
                        ),
                      if (!_isNew)
                        _RegionStaticField(
                          value: _formatDateTime(_region?.updatedAt),
                          label: 'Última alteração',
                          icon: Icons.update_rounded,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _RegionSectionCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Modelos de mensagens',
              subtitle: 'Textos usados nas rotinas de empréstimos e cobranças.',
              child: Column(
                children: [
                  _RegionTextField(
                    controller: _loanMessageController,
                    label: 'Mensagem do empréstimo',
                    icon: Icons.request_quote_outlined,
                    enabled: _fieldsEnabled,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  _RegionTextField(
                    controller: _refinancedMessageController,
                    label: 'Mensagem do refinanciamento',
                    icon: Icons.sync_alt_rounded,
                    enabled: _fieldsEnabled,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  _RegionTextField(
                    controller: _collectionMessageController,
                    label: 'Mensagem de cobrança',
                    icon: Icons.payments_outlined,
                    enabled: _fieldsEnabled,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  _RegionTextField(
                    controller: _collectionLinkController,
                    label: 'Mensagem de cobrança com link',
                    icon: Icons.link_rounded,
                    enabled: _fieldsEnabled,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  _RegionTextField(
                    controller: _overdueMessageController,
                    label: 'Mensagem de atraso',
                    icon: Icons.notification_important_outlined,
                    enabled: _fieldsEnabled,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _RegionSectionCard(
              icon: Icons.tune_rounded,
              title: 'Ajustes da região',
              subtitle: 'Regras aplicadas ao cadastro de clientes.',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.person_pin_circle_outlined,
                  color: context.colors.primary,
                  size: 20,
                ),
                title: Text(
                  'Exigir responsável pelo cliente',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Solicita o dono do cliente nas rotinas desta região.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
                trailing: Transform.scale(
                  scale: 0.75,
                  child: Switch.adaptive(
                    value: _clientOwnerRequired,
                    onChanged: _fieldsEnabled
                        ? (value) =>
                              setState(() => _clientOwnerRequired = value)
                        : null,
                    activeThumbColor: context.colors.primary,
                    activeTrackColor: context.colors.primary.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                onTap: _fieldsEnabled
                    ? () => setState(
                        () => _clientOwnerRequired = !_clientOwnerRequired,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final AppRegionDetail region = await _regionService.fetchRegion(
        widget.regionId!,
      );
      if (!mounted) return;
      setState(() {
        _applyRegion(region);
        _loading = false;
      });
    } on RegionServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  void _applyRegion(AppRegionDetail region) {
    _region = region;
    _descriptionController.text = region.description;
    _responsibleController.text = region.responsiblePeople ?? '';
    _parentController.text = region.parentDescription ?? '';
    _loanMessageController.text = region.loanMessage ?? '';
    _refinancedMessageController.text = region.refinancedLoanMessage ?? '';
    _collectionMessageController.text = region.collectionMessage ?? '';
    _collectionLinkController.text = region.collectionLinkMessage ?? '';
    _overdueMessageController.text = region.overdueMessage ?? '';
    _clientOwnerRequired = region.clientOwnerRequired;
  }

  void _startEditing() {
    if (!_canEdit || _isNew) return;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (_descriptionController.text.trim().isEmpty) {
      await _showDialog(
        title: 'Atenção',
        message: 'Informe a descrição da região.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> data = {
        'description': _descriptionController.text.trim(),
        'responsiblePeople': _nullable(_responsibleController.text),
        'parentDescription': _nullable(_parentController.text),
        'loanMessage': _nullable(_loanMessageController.text),
        'refinancedLoanMessage': _nullable(_refinancedMessageController.text),
        'collectionMessage': _nullable(_collectionMessageController.text),
        'collectionLinkMessage': _nullable(_collectionLinkController.text),
        'overdueMessage': _nullable(_overdueMessageController.text),
        'clientOwnerRequired': _clientOwnerRequired,
      };
      if (_isNew) {
        await _regionService.createRegion(data);
      } else {
        await _regionService.updateRegion(widget.regionId!, data);
      }
      if (!mounted) return;
      widget.onSaved?.call();
      if (_isNew) {
        widget.onCreated?.call();
        if (widget.onCreated == null) _goBack();
        return;
      }
      await _showDialog(
        title: 'Região salva',
        message: 'As alterações foram salvas com sucesso.',
      );
      if (!mounted) return;
      _goBack();
    } on RegionServiceException catch (error) {
      await _showDialog(
        title: 'Não foi possível salvar',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Excluir região?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'A exclusão só será permitida se a região não possuir dados vinculados.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _regionService.deleteRegion(widget.regionId!);
      if (!mounted) return;
      widget.onSaved?.call();
      _goBack();
    } on RegionServiceException catch (error) {
      await _showDialog(
        title: 'Não foi possível excluir',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _showDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showAppCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('OK', style: TextStyle(color: context.colors.primary)),
          ),
        ],
      ),
    );
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String? _nullable(String value) {
    final String result = value.trim();
    return result.isEmpty ? null : result;
  }

  String _formatDateTime(DateTime? value) => value == null
      ? '—'
      : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
}

class _RegionDetailHeader extends StatelessWidget {
  final String description;
  final int? regionId;
  final bool canEdit;
  final bool editing;
  final bool deleting;
  final VoidCallback? onDelete;

  const _RegionDetailHeader({
    required this.description,
    required this.regionId,
    required this.canEdit,
    required this.editing,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final String name = description.trim().isEmpty
        ? regionId == null
              ? 'Nova região'
              : 'Região #$regionId'
        : description.trim();
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  gradient: CustomFloatingActionButton.gradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      regionId == null
                          ? 'Preencha os dados para cadastrar'
                          : canEdit
                          ? editing
                                ? 'ID $regionId • editando região'
                                : 'ID $regionId • toque em editar para alterar'
                          : 'ID $regionId • somente leitura',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit && regionId != null)
                deleting
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            color: context.colors.error,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Excluir região',
                        onPressed: onDelete,
                        color: context.colors.error,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _RegionSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: context.colors.primary, size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            child,
          ],
        ),
      ),
    );
  }
}

class _RegionFieldGrid extends StatelessWidget {
  final bool twoColumns;
  final List<Widget> children;

  const _RegionFieldGrid({required this.twoColumns, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!twoColumns) {
      return Column(
        children: [
          for (int index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (int index = 0; index < children.length; index += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[index]),
              const SizedBox(width: 9),
              Expanded(
                child: index + 1 < children.length
                    ? children[index + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (index + 2 < children.length) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RegionTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _RegionTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: maxLines == 1 ? 1 : 2,
      onChanged: onChanged,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: context.colors.primary, size: 17),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 39,
          minHeight: 40,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 11,
        ),
        filled: true,
        fillColor: context.colors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: context.colors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _RegionStaticField extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _RegionStaticField({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: context.colors.primary, size: 17),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 39,
          minHeight: 40,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 11,
        ),
        filled: true,
        fillColor: context.colors.background,
        enabled: false,
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: context.colors.divider),
        ),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
      ),
    );
  }
}

class _RegionActionBar extends StatelessWidget {
  final bool canEdit;
  final bool isNew;
  final bool editing;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  const _RegionActionBar({
    required this.canEdit,
    required this.isNew,
    required this.editing,
    required this.saving,
    required this.onSave,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final secondaryButton = OutlinedButton(
      onPressed: onCancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.textSecondary,
        side: BorderSide(color: context.colors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(canEdit ? 'CANCELAR' : 'VOLTAR'),
    );
    final primaryButton = DecoratedBox(
      decoration: BoxDecoration(
        gradient: CustomFloatingActionButton.gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FilledButton(
        onPressed: isNew || editing ? onSave : onEdit,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: saving
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                isNew
                    ? 'CADASTRAR REGIÃO'
                    : editing
                    ? 'SALVAR ALTERAÇÕES'
                    : 'EDITAR REGIÃO',
              ),
      ),
    );

    return Material(
      color: context.colors.surface,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: mobile
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (canEdit) ...[
                          SizedBox(height: 42, child: primaryButton),
                          const SizedBox(height: 6),
                        ],
                        SizedBox(height: 42, child: secondaryButton),
                      ],
                    )
                  : SizedBox(
                      height: 42,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: secondaryButton),
                          if (canEdit) ...[
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: primaryButton),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionDetailMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RegionDetailMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.error,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textPrimary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
