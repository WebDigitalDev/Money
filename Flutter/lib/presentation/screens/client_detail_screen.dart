import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui show TextDirection;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:money/money.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:url_launcher/url_launcher.dart';

class ClientDetailScreenController {
  Future<void> Function()? _requestClose;

  bool requestClose() {
    final Future<void> Function()? callback = _requestClose;
    if (callback == null) return false;
    unawaited(callback());
    return true;
  }
}

class ClientDetailScreen extends StatefulWidget {
  final int? clientId;
  final bool showAppBar;
  final bool embedded;
  final bool showEmbeddedHeader;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final ValueChanged<AppClientDetail>? onCreated;
  final VoidCallback? onLoanCreated;
  final ClientDetailScreenController? controller;
  final TutorialGuideController? tutorialController;

  const ClientDetailScreen({
    super.key,
    this.clientId,
    this.showAppBar = true,
    this.embedded = false,
    this.showEmbeddedHeader = true,
    this.onBack,
    this.onSaved,
    this.onCreated,
    this.onLoanCreated,
    this.controller,
    this.tutorialController,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final ClientService _service = ClientService();
  final RegionService _regionService = RegionService();
  final TextEditingController _birthDateController = TextEditingController();
  final Map<String, TextEditingController> _fields = {
    for (final String key in const [
      'name',
      'legalName',
      'document',
      'stateRegistration',
      'email',
      'phone',
      'secondaryPhone',
      'homepage',
      'postalCode',
      'address',
      'number',
      'complement',
      'neighborhood',
      'collector',
      'googleMapsLink',
      'notes',
      'business',
      'facebook',
      'instagram',
    ])
      key: TextEditingController(),
  };

  AppClientDetail? _client;
  List<AppRegionOption> _regions = const [];
  List<AppClientContact> _contacts = const [];
  List<AppClientDocument> _documents = const [];
  final Map<int, Future<AppDownloadedDocument>> _documentDownloads = {};
  int? _regionId;
  AppCityOption? _city;
  DateTime? _birthDate;
  String _type = 'FISICA';
  bool _loading = true;
  bool _saving = false;
  bool _closing = false;
  bool _changingEnabled = false;
  bool _duplicating = false;
  bool _documentsLoading = false;
  bool _companyLookupLoading = false;
  String? _lastCompanyLookup;
  Timer? _companyLookupDebounce;
  String? _errorMessage;
  String? _formBaseline;
  int? _clientId;

  bool get _isNew => _clientId == null;
  bool get _tutorialMode => widget.tutorialController?.restrictData == true;
  bool get _canEdit {
    final AuthSession? session = AuthService().currentSession;
    return session?.administrator == true || session?.canEdit == true;
  }

  bool get _fieldsEnabled => _canEdit;

  @override
  void initState() {
    super.initState();
    _clientId = widget.clientId;
    widget.controller?._requestClose = _requestClose;
    for (final TextEditingController controller in _fields.values) {
      controller.addListener(_refreshFormState);
    }
    _birthDateController.addListener(_onBirthDateChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId && widget.clientId != _clientId) {
      _clientId = widget.clientId;
      unawaited(_load());
    }
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?._requestClose = null;
    widget.controller?._requestClose = _requestClose;
  }

  @override
  void dispose() {
    widget.controller?._requestClose = null;
    _companyLookupDebounce?.cancel();
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    _birthDateController.dispose();
    super.dispose();
  }

  void _refreshFormState() {
    if (mounted && !_loading) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String title = _isNew ? 'Novo cliente' : 'Detalhes do cliente';
    final Widget body = _buildBody();
    final Widget? actionBar = _loading || _errorMessage != null
        ? null
        : _ClientActionBar(
            primaryKey: widget.tutorialController?.clientNewLoanButtonKey,
            canEdit: _canEdit,
            saving: _saving,
            primaryLabel: _isNew
                ? 'SALVAR CLIENTE'
                : _hasChanges
                ? 'SALVAR ALTERAÇÕES'
                : 'NOVO EMPRÉSTIMO',
            secondaryLabel: 'CANCELAR',
            onPrimary: _saving || _changingEnabled
                ? null
                : _isNew
                ? _save
                : _hasChanges
                ? _save
                : _startNewLoan,
            onCancel: _saving || _changingEnabled ? null : _requestClose,
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
                onPressed: _requestClose,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 48,
                color: context.colors.primary,
              ),
              const SizedBox(height: 10),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          if (!widget.embedded || widget.showEmbeddedHeader)
            _ClientDetailHeader(
              name: _fields['name']!.text,
              status: _client?.status,
              clientEnabled: _client?.enabled ?? true,
              isNew: _isNew,
              canChangeEnabled: _canEdit && !_isNew,
              changingEnabled: _changingEnabled,
              canDuplicate: _canEdit && !_isNew,
              duplicating: _duplicating,
              onChangeEnabled: _confirmChangeEnabled,
              onDuplicate: _duplicateClient,
              onMap: _openMap,
            ),
          Material(
            color: context.colors.surface,
            child: TabBar(
              isScrollable: MediaQuery.sizeOf(context).width < 560,
              tabAlignment: MediaQuery.sizeOf(context).width < 560
                  ? TabAlignment.start
                  : TabAlignment.fill,
              indicatorColor: context.colors.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              labelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(height: 40, text: 'Identificação'),
                Tab(height: 40, text: 'Endereço'),
                Tab(height: 40, text: 'Observações'),
                Tab(height: 40, text: 'Documentos'),
                Tab(height: 40, text: 'Cobranças'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _identificationTab(),
                _addressTab(),
                _notesTab(),
                _documentsTab(),
                _collectionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _identificationTab() {
    final Widget nameField = _field(
      'name',
      'Nome *',
      Icons.person_outline_rounded,
      tutorialKey: widget.tutorialController?.clientNameKey,
      inputFormatters: const [_UpperCaseTextFormatter()],
    );
    final Widget phoneField = _field(
      'phone',
      _isNew ? 'Telefone/WhatsApp *' : 'Telefone/WhatsApp',
      Icons.phone_outlined,
      tutorialKey: widget.tutorialController?.clientPhoneKey,
      keyboardType: TextInputType.phone,
      inputFormatters: const [BrazilianPhoneInputFormatter()],
    );
    return _tabList([
      if (_client != null)
        ClientScoreCard(
          key: const ValueKey('client-score-card'),
          score: _client!.score,
        ),
      _ClientSectionCard(
        icon: Icons.map_outlined,
        title: 'Região',
        child: _buildRegionSelector(),
      ),
      _ClientSectionCard(
        icon: Icons.badge_outlined,
        title: 'Dados do cliente',
        child: _ClientFieldGrid(
          children: [
            _ClientDropdown<String>(
              value: _type,
              label: 'Tipo de pessoa',
              icon: Icons.person_outline_rounded,
              enabled: _fieldsEnabled,
              items: const [
                DropdownMenuItem(value: 'FISICA', child: Text('Pessoa física')),
                DropdownMenuItem(
                  value: 'JURIDICA',
                  child: Text('Pessoa jurídica'),
                ),
              ],
              onChanged: (value) => setState(() => _type = value ?? 'FISICA'),
            ),
            _field(
              'document',
              'CPF/CNPJ',
              Icons.credit_card_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: const [_CpfCnpjInputFormatter()],
              suffix: _companyLookupLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.primary,
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Consultar CNPJ',
                      onPressed:
                          _fieldsEnabled &&
                              _digits(_fields['document']!.text).length == 14
                          ? () => _lookupCompany(showInvalidMessage: true)
                          : null,
                      icon: const Icon(Icons.manage_search_rounded, size: 20),
                    ),
              onChanged: _onDocumentChanged,
            ),
            nameField,
            _field('legalName', 'Razão social', Icons.business_outlined),
            _field(
              'stateRegistration',
              'Inscrição estadual',
              Icons.receipt_long_outlined,
            ),
            _DateField(
              label: 'Data de nascimento',
              controller: _birthDateController,
              enabled: _fieldsEnabled,
              onTap: _pickBirthDate,
            ),
            _field(
              'email',
              'E-mail',
              Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            phoneField,
            _field(
              'secondaryPhone',
              'Telefone 2',
              Icons.phone_forwarded_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: const [BrazilianPhoneInputFormatter()],
            ),
            _field('homepage', 'Site', Icons.language_rounded),
            if (!_isNew)
              _StaticClientField(
                label: 'Criado em',
                value: _formatDateTime(_client?.createdAt),
                icon: Icons.event_available_outlined,
              ),
            if (!_isNew)
              _StaticClientField(
                label: 'Última alteração',
                value: _formatDateTime(_client?.updatedAt),
                icon: Icons.update_rounded,
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _addressTab() {
    return _tabList([
      _ClientSectionCard(
        icon: Icons.location_on_outlined,
        title: 'Localização',
        child: _ClientFieldGrid(
          children: [
            _field(
              'postalCode',
              _isNew ? 'CEP *' : 'CEP',
              Icons.local_post_office_outlined,
              keyboardType: TextInputType.number,
              suffix: _fieldsEnabled
                  ? IconButton(
                      tooltip: 'Buscar CEP',
                      onPressed: _lookupPostalCode,
                      icon: const Icon(Icons.search_rounded, size: 19),
                    )
                  : null,
            ),
            _CityField(
              city: _city,
              enabled: _fieldsEnabled,
              isRequired: _isNew,
              onTap: _selectCity,
            ),
            _field(
              'neighborhood',
              _isNew ? 'Bairro *' : 'Bairro',
              Icons.location_city_outlined,
            ),
            _field(
              'address',
              _isNew ? 'Endereço *' : 'Endereço',
              Icons.signpost_outlined,
            ),
            _field(
              'number',
              _isNew ? 'Número *' : 'Número',
              Icons.pin_outlined,
            ),
            _field(
              'complement',
              _isNew ? 'Complemento *' : 'Complemento',
              Icons.add_road_outlined,
            ),
            _field('collector', 'Referência/coletor', Icons.route_outlined),
            _field(
              'googleMapsLink',
              'Link Google Maps',
              Icons.map_outlined,
              keyboardType: TextInputType.url,
              fullWidth: true,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildRegionSelector() {
    final bool mobile = MediaQuery.sizeOf(context).width < 600;
    if (mobile) {
      return KeyedSubtree(
        key: widget.tutorialController?.clientRegionKey,
        child: _ClientRegionField(
          label: _selectedRegionName(),
          enabled: _fieldsEnabled,
          onTap: _selectRegionMobile,
        ),
      );
    }
    return KeyedSubtree(
      key: widget.tutorialController?.clientRegionKey,
      child: _ClientDropdown<int>(
        value: _regionId,
        label: 'Região *',
        icon: Icons.map_outlined,
        enabled: _fieldsEnabled,
        items: _regions
            .map(
              (region) => DropdownMenuItem(
                value: region.id,
                child: Text(
                  region.name.isEmpty ? 'Região #${region.id}' : region.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) => setState(() => _regionId = value),
      ),
    );
  }

  String _selectedRegionName() {
    for (final AppRegionOption region in _regions) {
      if (region.id == _regionId) {
        return region.name.isEmpty ? 'Região #${region.id}' : region.name;
      }
    }
    if (_regionId != null && _client?.regionName.isNotEmpty == true) {
      return _client!.regionName;
    }
    return 'Selecione uma região';
  }

  Future<void> _selectRegionMobile() async {
    if (!_fieldsEnabled) return;
    if (_regions.isEmpty) {
      await _showMessage(
        'Regiões indisponíveis',
        'Não foi possível carregar as regiões permitidas.',
      );
      return;
    }
    final int? selected = await showAppBottomSheet<int>(
      context: context,
      title: 'Selecionar região',
      subtitle: 'Escolha uma região para o cliente.',
      icon: Icons.map_outlined,
      heightFactor: 0.76,
      builder: (_) => _ClientRegionBottomSheet(
        regions: _regions,
        selectedRegionId: _regionId,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _regionId = selected);
    }
  }

  Widget _notesTab() {
    return _tabList([
      _ClientSectionCard(
        icon: Icons.notes_rounded,
        title: 'Informações complementares',
        child: _ClientFieldGrid(
          children: [
            _field('business', 'Comércio/empresa', Icons.storefront_outlined),
            _field('facebook', 'Facebook', Icons.facebook_rounded),
            _field('instagram', 'Instagram', Icons.photo_camera_outlined),
            _field(
              'notes',
              'Observações',
              Icons.notes_rounded,
              maxLines: 4,
              fullWidth: true,
            ),
          ],
        ),
      ),
      if (!_isNew)
        _ClientSectionCard(
          icon: Icons.contact_phone_outlined,
          title: 'Contatos',
          trailing: _canEdit
              ? IconButton.filledTonal(
                  tooltip: 'Adicionar contato',
                  onPressed: _showContactEditor,
                  style: IconButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                )
              : null,
          child: _contacts.isEmpty
              ? const _EmptySection(text: 'Nenhum contato cadastrado.')
              : Column(
                  children: [
                    for (final AppClientContact contact in _contacts)
                      _ContactTile(
                        contact: contact,
                        canEdit: _canEdit,
                        onEdit: () => _showContactEditor(contact),
                        onDelete: () => _deleteContact(contact),
                      ),
                  ],
                ),
        ),
    ]);
  }

  Widget _documentsTab() {
    return _tabList([
      _ClientSectionCard(
        icon: Icons.folder_copy_outlined,
        title: 'Documentos do cliente',
        trailing: !_isNew && _canEdit
            ? IconButton.filledTonal(
                tooltip: 'Enviar documento',
                onPressed: _documentsLoading ? null : _uploadDocument,
                style: IconButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.colors.primary.withValues(
                    alpha: 0.45,
                  ),
                  disabledForegroundColor: Colors.white70,
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 19),
              )
            : null,
        child: _isNew
            ? const _EmptySection(
                text: 'Salve o cliente antes de anexar documentos.',
              )
            : _documentsLoading
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: context.colors.primary,
                  ),
                ),
              )
            : _documents.isEmpty
            ? const _EmptySection(text: 'Nenhum documento anexado.')
            : LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _documents.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: constraints.maxWidth >= 700 ? 230 : 190,
                    mainAxisExtent: 176,
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                  ),
                  itemBuilder: (context, index) {
                    final AppClientDocument document = _documents[index];
                    return _DocumentCard(
                      document: document,
                      canEdit: _canEdit,
                      loadFile: () => _loadDocument(document),
                      onDownload: () => _downloadDocument(document),
                      onEdit: () => _renameDocument(document),
                      onDelete: () => _deleteDocument(document),
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _collectionsTab() {
    final int? clientId = _clientId;
    if (clientId == null) {
      return _tabList([
        const _ClientSectionCard(
          icon: Icons.route_outlined,
          title: 'Cobranças do cliente',
          child: _EmptySection(
            text: 'Salve o cliente antes de consultar cobranças.',
          ),
        ),
      ]);
    }
    return ClientCollectionsPanel(
      key: ValueKey('client-collections-$clientId'),
      clientId: clientId,
    );
  }

  Widget _tabList(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String fieldName,
    String label,
    IconData icon, {
    Key? tutorialKey,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool fullWidth = false,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) => _ClientTextField(
    key: tutorialKey,
    controller: _fields[fieldName]!,
    label: label,
    icon: icon,
    enabled: _fieldsEnabled,
    keyboardType: keyboardType,
    maxLines: maxLines,
    fullWidth: fullWidth,
    suffix: suffix,
    inputFormatters: inputFormatters,
    onChanged:
        onChanged ?? (fieldName == 'name' ? (_) => setState(() {}) : null),
  );

  void _onDocumentChanged(String value) {
    _companyLookupDebounce?.cancel();
    final String digits = _digits(value);
    setState(() {
      if (digits.length <= 11) _type = 'FISICA';
      if (digits.length == 14) _type = 'JURIDICA';
    });
    if (digits.length != 14 || digits == _lastCompanyLookup) return;
    _companyLookupDebounce = Timer(
      const Duration(milliseconds: 550),
      () => _lookupCompany(showInvalidMessage: false),
    );
  }

  Future<void> _lookupCompany({required bool showInvalidMessage}) async {
    final String document = _digits(_fields['document']!.text);
    if (!_isValidCnpj(document)) {
      if (showInvalidMessage) {
        await _showMessage(
          'CNPJ inválido',
          'Confira os 14 números informados e tente novamente.',
        );
      }
      return;
    }
    _companyLookupDebounce?.cancel();
    setState(() => _companyLookupLoading = true);
    try {
      final AppCompanyLookup company = await _service.fetchCompany(document);
      if (!mounted || _digits(_fields['document']!.text) != document) return;
      _lastCompanyLookup = document;
      _type = 'JURIDICA';
      _setCompanyField('name', company.tradeName ?? company.legalName);
      _setCompanyField('legalName', company.legalName);
      _setCompanyField('stateRegistration', company.stateRegistration);
      _setCompanyField('email', company.email);
      _setCompanyField('phone', formatBrazilianPhone(company.primaryPhone));
      _setCompanyField(
        'secondaryPhone',
        formatBrazilianPhone(company.secondaryPhone),
      );
      _setCompanyField(
        'postalCode',
        company.postalCode == null ? null : '${company.postalCode}',
      );
      _setCompanyField('address', company.address);
      _setCompanyField('number', company.number);
      _setCompanyField('complement', company.complement);
      _setCompanyField('neighborhood', company.neighborhood);
      if (company.cityIbgeCode != null) {
        final List<AppCityOption> cities = await _service.searchCities(
          ibgeCode: company.cityIbgeCode,
        );
        if (mounted &&
            cities.isNotEmpty &&
            _digits(_fields['document']!.text) == document) {
          _city = cities.first;
        }
      }
      if (mounted) setState(() {});
    } on ClientServiceException catch (error) {
      if (mounted) {
        await _showMessage('Consulta de CNPJ', error.message);
      }
    } finally {
      if (mounted) setState(() => _companyLookupLoading = false);
    }
  }

  void _setCompanyField(String key, String? value) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) _fields[key]!.text = normalized;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      if (_tutorialMode) await AuthService().beginTutorial();
      final List<Object?> loaded = await Future.wait<Object?>([
        _regionService.fetchOptions(
          force: _tutorialMode,
          tutorialMode: _tutorialMode,
        ),
        if (_isNew)
          Future<AppClientDetail?>.value()
        else
          _service.fetchClient(_clientId!),
      ]);
      final List<AppRegionOption> availableRegions =
          loaded[0] as List<AppRegionOption>;
      final List<AppRegionOption> regions = _tutorialMode
          ? availableRegions
                .where(
                  (region) =>
                      TutorialGuideController.isTutorialRegionName(region.name),
                )
                .toList(growable: false)
          : availableRegions;
      final AppClientDetail? client = loaded[1] as AppClientDetail?;
      if (!mounted) return;
      _regions = regions;
      if (client != null) {
        _client = client;
        _populate(client);
      } else if (_regions.length == 1) {
        _regionId = _regions.first.id;
      }
      _formBaseline = _formFingerprint();
      setState(() => _loading = false);
      if (client != null) unawaited(_loadRelatedData(client.id));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadRelatedData(int clientId) async {
    try {
      final List<Object> related = await Future.wait<Object>([
        _service.fetchContacts(clientId),
        _service.fetchDocuments(clientId),
      ]);
      if (!mounted || _client?.id != clientId) return;
      setState(() {
        _contacts = related[0] as List<AppClientContact>;
        _documents = related[1] as List<AppClientDocument>;
        _documentDownloads.clear();
      });
    } on Object {
      // Esses dados pertencem a outras abas e não bloqueiam a identificação.
    }
  }

  void _populate(AppClientDetail client) {
    final Map<String, String?> values = {
      'name': client.name,
      'legalName': client.legalName,
      'document': _formatCpfCnpj(client.document ?? ''),
      'stateRegistration': client.stateRegistration,
      'email': client.email,
      'phone': formatBrazilianPhone(client.phone),
      'secondaryPhone': formatBrazilianPhone(client.secondaryPhone),
      'homepage': client.homepage,
      'postalCode': client.postalCode == 0
          ? null
          : client.postalCode.toString().padLeft(8, '0'),
      'address': client.address,
      'number': client.number,
      'complement': client.complement,
      'neighborhood': client.neighborhood,
      'collector': client.collector,
      'googleMapsLink': client.googleMapsLink ?? _legacyMapLink(client),
      'notes': client.notes,
      'business': client.business,
      'facebook': client.facebook,
      'instagram': client.instagram,
    };
    for (final MapEntry<String, String?> entry in values.entries) {
      _fields[entry.key]!.text = entry.value ?? '';
    }
    _type = _personTypeValue(client.type, client.document);
    _birthDate = client.birthDate;
    _birthDateController.text = _birthDate == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(_birthDate!);
    _regionId = client.regionId;
    if (client.cityId != null) {
      _city = AppCityOption(
        id: client.cityId!,
        ibgeCode: null,
        name: client.cityName ?? '',
        state: client.cityState ?? '',
        displayName: [
          client.cityName,
          client.cityState,
        ].whereType<String>().where((value) => value.isNotEmpty).join(' - '),
      );
    }
  }

  Future<bool> _save({bool showSuccess = true}) async {
    final bool creating = _isNew;
    final String name = _fields['name']!.text.trim();
    final String phone = _digits(_fields['phone']!.text);
    if (name.isEmpty) {
      await _showMessage(
        'Dados obrigatórios',
        'Informe o nome do cliente antes de salvar.',
      );
      return false;
    }
    if (_regionId == null) {
      await _showMessage(
        'Dados obrigatórios',
        'Selecione a região do cliente antes de salvar.',
      );
      return false;
    }
    if (_birthDateController.text.trim().isNotEmpty && _birthDate == null) {
      await _showMessage(
        'Data de nascimento inválida',
        'Informe uma data válida no formato dia/mês/ano.',
      );
      return false;
    }
    if (_isNew && phone.isEmpty) {
      await _showMessage(
        'Dados obrigatórios',
        'Informe o Telefone/WhatsApp do cliente antes de salvar.',
      );
      return false;
    }
    if (creating) {
      final String postalCode = _digits(_fields['postalCode']!.text);
      if (postalCode.length != 8) {
        await _showMessage(
          'Dados obrigatórios',
          'Informe um CEP válido com oito números antes de salvar.',
        );
        return false;
      }
      if (_city == null) {
        await _showMessage(
          'Dados obrigatórios',
          'Selecione a cidade do cliente antes de salvar.',
        );
        return false;
      }
      if (_fields['neighborhood']!.text.trim().isEmpty) {
        await _showMessage(
          'Dados obrigatórios',
          'Informe o bairro do cliente antes de salvar.',
        );
        return false;
      }
      if (_fields['address']!.text.trim().isEmpty) {
        await _showMessage(
          'Dados obrigatórios',
          'Informe o endereço do cliente antes de salvar.',
        );
        return false;
      }
      if (_fields['number']!.text.trim().isEmpty) {
        await _showMessage(
          'Dados obrigatórios',
          'Informe o número do endereço antes de salvar.',
        );
        return false;
      }
      if (_fields['complement']!.text.trim().isEmpty) {
        await _showMessage(
          'Dados obrigatórios',
          'Informe o complemento do endereço antes de salvar.',
        );
        return false;
      }
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> data = {
        'name': name,
        'legalName': _nullable('legalName'),
        'document': _nullableDigits('document'),
        'email': _nullable('email'),
        'type': _type,
        'stateRegistration': _nullable('stateRegistration'),
        'birthDate': _birthDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_birthDate!),
        'phone': _nullableDigits('phone'),
        'secondaryPhone': _nullableDigits('secondaryPhone'),
        'homepage': _nullable('homepage'),
        'postalCode': _integer('postalCode'),
        'cityId': _city?.id,
        'address': _nullable('address'),
        'number': _nullable('number'),
        'complement': _nullable('complement'),
        'neighborhood': _nullable('neighborhood'),
        'collector': _nullable('collector'),
        'googleMapsLink': _nullable('googleMapsLink'),
        'latitude': _client?.latitude,
        'longitude': _client?.longitude,
        'businessLatitude': _client?.businessLatitude,
        'businessLongitude': _client?.businessLongitude,
        'regionId': _regionId,
        'notes': _nullable('notes'),
        'business': _nullable('business'),
        'facebook': _nullable('facebook'),
        'instagram': _nullable('instagram'),
      };
      final AppClientDetail saved = _isNew
          ? await _service.createClient(data)
          : await _service.updateClient(_clientId!, data);
      if (!mounted) return false;
      _client = saved;
      _clientId = saved.id;
      _populate(saved);
      _formBaseline = _formFingerprint();
      setState(() => _saving = false);
      widget.onSaved?.call();
      if (creating) widget.onCreated?.call(saved);
      if (showSuccess) {
        await _showMessage(
          creating ? 'Cliente cadastrado' : 'Cliente atualizado',
          creating
              ? 'O novo cliente foi cadastrado com sucesso.'
              : 'As informações foram atualizadas com sucesso.',
        );
      }
      return true;
    } on ClientServiceException catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      await _showMessage('Não foi possível salvar', error.message);
      return false;
    }
  }

  Future<void> _confirmChangeEnabled() async {
    final bool enabling = _client?.enabled == false;
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(enabling ? 'Ativar cliente?' : 'Desativar cliente?'),
        content: Text(
          enabling ? 'O cliente poderá receber novos empréstimos novamente.' : 'O cliente não poderá receber novos empréstimos enquanto estiver desativado. Os dados e o histórico serão preservados.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: !enabling,
            onPressed: () => Navigator.pop(context, true),
            child: Text(enabling ? 'Ativar' : 'Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _changingEnabled = true);
    try {
      final AppClientDetail updated = await _service.setClientEnabled(
        _clientId!,
        enabling,
      );
      if (!mounted) return;
      setState(() {
        _client = updated;
        _changingEnabled = false;
      });
      widget.onSaved?.call();
    } on ClientServiceException catch (error) {
      if (!mounted) return;
      setState(() => _changingEnabled = false);
      await _showMessage(
        enabling ? 'Não foi possível ativar' : 'Não foi possível desativar',
        error.message,
      );
    }
  }

  Future<void> _pickBirthDate() async {
    if (!_fieldsEnabled) return;
    final DateTime? selected = await showAppDatePickerBottomSheet(
      context: context,
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      _birthDateController.text = DateFormat('dd/MM/yyyy').format(selected);
    }
  }

  void _onBirthDateChanged() {
    _birthDate = _parseClientBirthDate(_birthDateController.text);
    _refreshFormState();
  }

  Future<void> _selectCity() async {
    if (!_fieldsEnabled) return;
    final AppCityOption? selected = await showClientCitySelection(
      context: context,
      service: _service,
    );
    if (selected != null && mounted) setState(() => _city = selected);
  }

  Future<void> _lookupPostalCode() async {
    final String cep = _fields['postalCode']!.text.replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (cep.length != 8) {
      await _showMessage('CEP inválido', 'Digite os oito números do CEP.');
      return;
    }
    try {
      final http.Response response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['erro'] == true) {
        throw const FormatException();
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
      _fields['address']!.text = data['logradouro']?.toString() ?? '';
      _fields['neighborhood']!.text = data['bairro']?.toString() ?? '';
      final int? ibge = int.tryParse(data['ibge']?.toString() ?? '');
      if (ibge != null) {
        final List<AppCityOption> options = await _service.searchCities(
          ibgeCode: ibge,
        );
        if (options.isNotEmpty) _city = options.first;
      }
      if (mounted) setState(() {});
    } on Object {
      if (mounted) {
        await _showMessage(
          'CEP não encontrado',
          'Não foi possível consultar esse CEP agora.',
        );
      }
    }
  }

  Future<void> _showContactEditor([AppClientContact? contact]) async {
    final Map<String, String>? data = await showAppCupertinoDialog(
      context: context,
      builder: (_) => _ClientContactDialog(contact: contact),
    );
    final String name = data?['name']?.trim() ?? '';
    if (data != null && name.isNotEmpty) {
      try {
        final AppClientContact saved = await _service.saveContact(_clientId!, {
          'name': name,
          'phone': brazilianPhoneDigits(data['phone'] ?? '').isEmpty
              ? null
              : brazilianPhoneDigits(data['phone'] ?? ''),
          'type': _nullableText(data['type'] ?? ''),
          'notes': _nullableText(data['notes'] ?? ''),
        }, contactId: contact?.id);
        if (mounted) {
          setState(() {
            final List<AppClientContact> updated = [..._contacts];
            final int index = updated.indexWhere((item) => item.id == saved.id);
            if (index < 0) {
              updated.add(saved);
            } else {
              updated[index] = saved;
            }
            _contacts = updated;
          });
        }
      } on ClientServiceException catch (error) {
        if (mounted) {
          await _showMessage('Erro ao salvar contato', error.message);
        }
      }
    }
  }

  Future<void> _deleteContact(AppClientContact contact) async {
    if (!await _confirm('Excluir contato?', contact.name)) return;
    try {
      await _service.deleteContact(_clientId!, contact.id);
      if (mounted) {
        setState(
          () => _contacts = _contacts
              .where((item) => item.id != contact.id)
              .toList(growable: false),
        );
      }
    } on ClientServiceException catch (error) {
      if (mounted) await _showMessage('Erro ao excluir contato', error.message);
    }
  }

  Future<void> _uploadDocument() async {
    final XFile? file = await openFile();
    if (file == null) return;
    final List<int> fileBytes = await file.readAsBytes();
    final String? description = await _askText(
      'Descrição do documento',
      file.name,
    );
    if (description == null) return;
    setState(() => _documentsLoading = true);
    try {
      await _service.uploadDocument(
        clientId: _clientId!,
        bytes: Uint8List.fromList(fileBytes),
        fileName: file.name,
        description: description,
      );
      final List<AppClientDocument> documents = await _service.fetchDocuments(
        _clientId!,
      );
      if (mounted) {
        setState(() {
          _documents = documents;
          _documentDownloads.clear();
        });
      }
    } on ClientServiceException catch (error) {
      if (mounted) await _showMessage('Erro no envio', error.message);
    } finally {
      if (mounted) setState(() => _documentsLoading = false);
    }
  }

  Future<void> _downloadDocument(AppClientDocument document) async {
    if (!document.available) {
      await _showMessage(
        'Arquivo indisponível',
        'O registro foi preservado, mas o arquivo original não existe na réplica atual.',
      );
      return;
    }
    try {
      final AppDownloadedDocument file = await _loadDocument(document);
      final XFile downloadedFile = XFile.fromData(
        file.bytes,
        mimeType: file.contentType,
        name: file.fileName,
      );
      if (kIsWeb) {
        await downloadedFile.saveTo('');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [downloadedFile],
          fileNameOverrides: [file.fileName],
          title: document.description,
        ),
      );
    } on Object catch (error) {
      if (mounted) await _showMessage('Erro no download', error.toString());
    }
  }

  Future<AppDownloadedDocument> _loadDocument(AppClientDocument document) {
    return _documentDownloads.putIfAbsent(document.id, () async {
      try {
        return await _service.downloadDocument(_clientId!, document);
      } catch (_) {
        _documentDownloads.remove(document.id);
        rethrow;
      }
    });
  }

  Future<void> _renameDocument(AppClientDocument document) async {
    final String? description = await _askText(
      'Descrição do documento',
      document.description,
    );
    if (description == null) return;
    try {
      final AppClientDocument updated = await _service.updateDocument(
        _clientId!,
        document.id,
        description,
      );
      if (mounted) {
        setState(() {
          _documents = _documents
              .map((item) => item.id == updated.id ? updated : item)
              .toList(growable: false);
        });
      }
    } on ClientServiceException catch (error) {
      if (mounted) await _showMessage('Erro ao atualizar', error.message);
    }
  }

  Future<void> _deleteDocument(AppClientDocument document) async {
    if (!await _confirm('Excluir documento?', document.description)) return;
    try {
      await _service.deleteDocument(_clientId!, document.id);
      if (mounted) {
        setState(() {
          _documentDownloads.remove(document.id);
          _documents = _documents
              .where((item) => item.id != document.id)
              .toList(growable: false);
        });
      }
    } on ClientServiceException catch (error) {
      if (mounted) await _showMessage('Erro ao excluir', error.message);
    }
  }

  Future<void> _openMap() async {
    final String? link = _nullable('googleMapsLink');
    final Uri? uri = link == null ? null : _mapUri(link);
    if (uri == null) {
      await _showMessage(
        'Localização não cadastrada',
        'Informe um link válido do Google Maps para abrir o mapa.',
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      await _showMessage('Mapa indisponível', 'Não foi possível abrir o mapa.');
    }
  }

  Future<void> _duplicateClient() async {
    final int? sourceId = _clientId;
    if (sourceId == null || _duplicating) return;
    setState(() => _duplicating = true);
    try {
      final List<AppRegionOption> regions = await _service
          .fetchDuplicateRegions(sourceId);
      if (!mounted) return;
      if (regions.isEmpty) {
        await _showMessage(
          'Nenhuma região disponível',
          'Este cliente já existe em todas as regiões permitidas para você.',
        );
        return;
      }
      final int? regionId = await showAppBottomSheet<int>(
        context: context,
        title: 'Duplicar cliente',
        subtitle: 'Escolha a nova região. Regiões onde o CPF/CNPJ já existe foram ocultadas.',
        icon: Icons.content_copy_rounded,
        heightFactor: 0.76,
        builder: (_) => _ClientRegionBottomSheet(
          regions: regions,
          selectedRegionId: null,
          actionLabel: 'DUPLICAR',
        ),
      );
      if (regionId == null || !mounted) return;
      final AppClientDetail copy = await _service.duplicateClient(
        sourceId,
        regionId,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      await _showMessage(
        'Cliente duplicado',
        '${copy.name} foi criado em ${copy.regionName}.',
      );
    } on ClientServiceException catch (error) {
      if (mounted) {
        await _showMessage('Não foi possível duplicar', error.message);
      }
    } finally {
      if (mounted) setState(() => _duplicating = false);
    }
  }

  Future<void> _startNewLoan() async {
    if (_saving || _closing || _client == null) return;
    if (_hasChanges) return;
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Novo Empréstimo'),
            content: Text(
              'Deseja iniciar um novo empréstimo para ${_client!.name}?',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Não'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sim'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final AppClientDetail client = _client!;
    final bool? created = await openLoanDetailScreen(
      context: context,
      clientId: client.id,
      clientName: client.name,
      regionId: client.regionId,
      regionName: client.regionName,
    );
    LoanService().clearCache();
    widget.onSaved?.call();
    if (created == true) {
      widget.onLoanCreated?.call();
      return;
    }
    if (mounted) unawaited(_load());
  }

  Future<bool> _confirm(String title, String content) async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _askText(String title, String initial) async {
    final String? value = await showAppCupertinoTextInputDialog(
      context: context,
      title: title,
      placeholder: title,
      initialValue: initial,
    );
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _showMessage(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  String? _nullable(String key) => _nullableText(_fields[key]!.text);
  String? _nullableDigits(String key) {
    final String value = _digits(_fields[key]!.text);
    return value.isEmpty ? null : value;
  }

  int? _integer(String key) =>
      int.tryParse(_fields[key]!.text.replaceAll(RegExp(r'\D'), ''));

  Future<void> _requestClose() async {
    if (_saving || _changingEnabled || _closing) return;
    _closing = true;
    if (_formBaseline == null || _hasChanges) {
      final bool discard = await _confirmDiscardChanges();
      if (!mounted) return;
      if (!discard) {
        _closing = false;
        return;
      }
    }
    if (mounted) _leaveScreen();
  }

  bool get _hasChanges =>
      _formBaseline != null && _formFingerprint() != _formBaseline;

  String _formFingerprint() => [
    for (final String key in _fields.keys) _fields[key]!.text.trim(),
    _type,
    _regionId?.toString() ?? '',
    _city?.id.toString() ?? '',
    _birthDateController.text.trim(),
  ].join('\u001f');

  Future<bool> _confirmDiscardChanges() async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Descartar alterações?'),
          content: const Text(
            'As alterações realizadas no cliente serão perdidas.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continuar editando'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;

  void _leaveScreen() {
    if (widget.onBack != null) {
      widget.onBack!.call();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}

class _ClientDetailHeader extends StatelessWidget {
  final String name;
  final AppClientStatus? status;
  final bool clientEnabled;
  final bool isNew;
  final bool canChangeEnabled;
  final bool changingEnabled;
  final bool canDuplicate;
  final bool duplicating;
  final VoidCallback onChangeEnabled;
  final VoidCallback onDuplicate;
  final VoidCallback onMap;

  const _ClientDetailHeader({
    required this.name,
    required this.status,
    required this.clientEnabled,
    required this.isNew,
    required this.canChangeEnabled,
    required this.changingEnabled,
    required this.canDuplicate,
    required this.duplicating,
    required this.onChangeEnabled,
    required this.onDuplicate,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    final String displayName = name.trim().isEmpty ? 'Novo cliente' : name;
    return Material(
      color: context.colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4B7D60), Color(0xFF76B475)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!isNew)
                        Text(
                          switch (status) {
                            _ when !clientEnabled => 'Cliente desativado',
                            AppClientStatus.active => 'Cliente ativo',
                            AppClientStatus.withoutLoans => 'Sem empréstimos',
                            AppClientStatus.missing => 'Desaparecido',
                            _ => 'Cliente',
                          },
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isNew) ...[
                  if (canDuplicate)
                    IconButton(
                      tooltip: 'Duplicar cliente',
                      onPressed: duplicating ? null : onDuplicate,
                      icon: duplicating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _DuplicateClientGlyph(
                              color: context.colors.primary,
                            ),
                    ),
                  IconButton(
                    tooltip: 'Abrir no mapa',
                    onPressed: onMap,
                    icon: Icon(
                      Icons.map_outlined,
                      color: context.colors.primary,
                    ),
                  ),
                ],
                if (canChangeEnabled)
                  IconButton(
                    tooltip: clientEnabled
                        ? 'Desativar cliente'
                        : 'Ativar cliente',
                    onPressed: changingEnabled ? null : onChangeEnabled,
                    icon: changingEnabled
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : clientEnabled
                        ? Icon(
                            Icons.person_off_outlined,
                            color: context.colors.error,
                          )
                        : _ActivateClientGlyph(color: context.colors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivateClientGlyph extends StatelessWidget {
  final Color color;

  const _ActivateClientGlyph({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Icon(Icons.person_outline_rounded, color: color, size: 22),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Icon(Icons.add_circle_rounded, color: color, size: 12),
          ),
        ],
      ),
    );
  }
}

class _DuplicateClientGlyph extends StatelessWidget {
  final Color color;

  const _DuplicateClientGlyph({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 6,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.7),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border.all(color: color, width: 1.7),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          Positioned(
            right: 5.5,
            top: 7.5,
            child: Container(width: 6, height: 1.7, color: color),
          ),
          Positioned(
            right: 7.65,
            top: 5.35,
            child: Container(width: 1.7, height: 6, color: color),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class ClientScoreCard extends StatelessWidget {
  final AppClientScore score;

  const ClientScoreCard({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final _ClientScoreLevel level = _ClientScoreLevel.forPoints(score.points);
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: r'R$',
    );
    return _ClientSectionCard(
      icon: Icons.speed_rounded,
      title: 'Score do cliente',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: level.color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          level.label,
          style: TextStyle(
            color: level.color,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double gaugeWidth = math.min(
            205,
            math.max(138, constraints.maxWidth * .46),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: gaugeWidth,
                child: _ClientScoreGauge(score: score.points),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    _ClientScoreMetric(
                      icon: Icons.history_rounded,
                      label: 'Dias acumulados em atraso',
                      value:
                          '${score.overdueDays} dia${score.overdueDays == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 8),
                    _ClientScoreMetric(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Dívida total atual',
                      value: currency.format(score.totalDebt),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClientScoreMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ClientScoreMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.background.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  key: ValueKey<String>('client-score-metric-$label'),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientScoreGauge extends StatelessWidget {
  final int score;

  const _ClientScoreGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    final _ClientScoreLevel level = _ClientScoreLevel.forPoints(score);
    return Semantics(
      label: 'Score do cliente: $score pontos, ${level.label}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 102,
            width: double.infinity,
            child: CustomPaint(
              painter: _ClientScoreGaugePainter(
                score: score,
                tickColor: context.colors.textSecondary,
                trackColor: context.colors.divider,
              ),
            ),
          ),
          Text(
            '$score pontos',
            key: const ValueKey('client-score-points'),
            style: TextStyle(
              color: level.color,
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientScoreGaugePainter extends CustomPainter {
  static const Color _red = Color(0xFFE24B4B);
  static const Color _yellow = Color(0xFFF2B33D);
  static const Color _green = Color(0xFF42B96B);

  final int score;
  final Color tickColor;
  final Color trackColor;

  const _ClientScoreGaugePainter({
    required this.score,
    required this.tickColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = math.min(size.width * .39, size.height * .69);
    final Offset center = Offset(size.width / 2, size.height - 10);
    final Rect arcBounds = Rect.fromCircle(center: center, radius: radius);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..color = trackColor.withValues(alpha: .38);
    canvas.drawArc(arcBounds, math.pi, math.pi, false, track);

    final Paint gradient = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: math.pi,
        endAngle: math.pi * 2,
        colors: [_red, _yellow, _green],
        stops: [0, .5, 1],
      ).createShader(arcBounds);
    canvas.drawArc(arcBounds, math.pi, math.pi, false, gradient);

    final Paint tick = Paint()
      ..color = tickColor.withValues(alpha: .88)
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    for (int points = 0; points <= 100; points += 20) {
      final double angle = math.pi + math.pi * (points / 100);
      final Offset inner =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 13);
      final Offset outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius + 2);
      canvas.drawLine(inner, outer, tick);
      _paintTickLabel(canvas, size, center, radius, angle, points);
    }

    final int boundedScore = score.clamp(0, 100);
    final double needleAngle = math.pi + math.pi * (boundedScore / 100);
    final Offset needleEnd =
        center +
        Offset(math.cos(needleAngle), math.sin(needleAngle)) * (radius - 17);
    final Color needleColor = _ClientScoreLevel.forPoints(boundedScore).color;
    final Paint needle = Paint()
      ..color = needleColor
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needle);
    canvas.drawCircle(center, 6.2, Paint()..color = needleColor);
    canvas.drawCircle(center, 2.3, Paint()..color = Colors.white);
  }

  void _paintTickLabel(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double angle,
    int points,
  ) {
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: '$points',
        style: TextStyle(
          color: tickColor,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final Offset anchor =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 13);
    final double left = (anchor.dx - label.width / 2).clamp(
      0,
      size.width - label.width,
    );
    final double top = (anchor.dy - label.height / 2).clamp(
      0,
      size.height - label.height,
    );
    label.paint(canvas, Offset(left, top));
  }

  @override
  bool shouldRepaint(covariant _ClientScoreGaugePainter oldDelegate) =>
      score != oldDelegate.score ||
      tickColor != oldDelegate.tickColor ||
      trackColor != oldDelegate.trackColor;
}

final class _ClientScoreLevel {
  final String label;
  final Color color;

  const _ClientScoreLevel._(this.label, this.color);

  static _ClientScoreLevel forPoints(int points) {
    if (points < 40) {
      return const _ClientScoreLevel._('Risco alto', Color(0xFFE24B4B));
    }
    if (points < 60) {
      return const _ClientScoreLevel._('Atenção', Color(0xFFF2A51F));
    }
    return const _ClientScoreLevel._('Bom', Color(0xFF35A95E));
  }
}

class _ClientSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _ClientSectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: context.colors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 18, color: context.colors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientFieldGrid extends StatelessWidget {
  final List<Widget> children;

  const _ClientFieldGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool twoColumns = constraints.maxWidth >= 650;
        if (!twoColumns) {
          return Column(children: [for (final Widget child in children) child]);
        }
        final List<Widget> rows = [];
        for (int index = 0; index < children.length; index += 2) {
          final Widget first = children[index];
          if (first is _ClientTextField && first.fullWidth) {
            rows.add(first);
            continue;
          }
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: first),
                const SizedBox(width: 9),
                Expanded(
                  child: index + 1 < children.length
                      ? children[index + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _ClientTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool fullWidth;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _ClientTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    this.keyboardType,
    this.maxLines = 1,
    this.fullWidth = false,
    this.suffix,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: _inputDecoration(context, label, icon, suffix: suffix),
      ),
    );
  }
}

class _ClientDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final IconData icon;
  final bool enabled;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _ClientDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T>(
        initialValue: items.any((item) => item.value == value) ? value : null,
        items: items,
        onChanged: enabled ? onChanged : null,
        isExpanded: true,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
        decoration: _inputDecoration(context, label, icon),
      ),
    );
  }
}

class _ClientRegionField extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ClientRegionField({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: _inputDecoration(
            context,
            'Região *',
            Icons.map_outlined,
            suffix: Icon(
              Icons.arrow_drop_down_rounded,
              color: enabled
                  ? context.colors.textSecondary
                  : context.colors.textPlaceholder,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: label == 'Selecione uma região'
                  ? context.colors.textPlaceholder
                  : context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientRegionBottomSheet extends StatefulWidget {
  final List<AppRegionOption> regions;
  final int? selectedRegionId;
  final String actionLabel;

  const _ClientRegionBottomSheet({
    required this.regions,
    required this.selectedRegionId,
    this.actionLabel = 'APLICAR',
  });

  @override
  State<_ClientRegionBottomSheet> createState() =>
      _ClientRegionBottomSheetState();
}

class _ClientRegionBottomSheetState extends State<_ClientRegionBottomSheet> {
  int? _selectedRegionId;

  @override
  void initState() {
    super.initState();
    _selectedRegionId = widget.selectedRegionId;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: context.colors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                'REGIÕES',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              const Text('Seleção única', style: TextStyle(fontSize: 9.8)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Material(
              color: context.colors.background,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: context.colors.divider),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: widget.regions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: context.colors.divider),
                itemBuilder: (context, index) {
                  final AppRegionOption region = widget.regions[index];
                  final bool selected = _selectedRegionId == region.id;
                  return ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onTap: () => setState(() => _selectedRegionId = region.id),
                    title: Text(
                      region.name.isEmpty
                          ? 'Região #${region.id}'
                          : region.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: selected
                          ? context.colors.primary
                          : context.colors.textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Divider(height: 1, color: context.colors.divider),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: SizedBox(
              height: 38,
              child: FilledButton(
                onPressed: _selectedRegionId == null
                    ? null
                    : () => Navigator.pop(context, _selectedRegionId),
                child: Text(widget.actionLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.datetime,
      inputFormatters: const [_ClientBirthDateInputFormatter()],
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 13),
      decoration: _inputDecoration(
        context,
        label,
        Icons.cake_outlined,
        suffix: IconButton(
          tooltip: 'Selecionar data',
          onPressed: enabled ? onTap : null,
          icon: Icon(
            Icons.calendar_month_outlined,
            size: 20,
            color: context.colors.textSecondary,
          ),
        ),
      ).copyWith(hintText: 'dd/mm/aaaa'),
    ),
  );
}

class _ClientBirthDateInputFormatter extends TextInputFormatter {
  const _ClientBirthDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final StringBuffer formatted = StringBuffer();
    for (int index = 0; index < digits.length; index++) {
      if (index == 2 || index == 4) formatted.write('/');
      formatted.write(digits[index]);
    }
    final String text = formatted.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

DateTime? _parseClientBirthDate(String value) {
  if (value.trim().length != 10) return null;
  try {
    final DateTime date = DateFormat('dd/MM/yyyy').parseStrict(value.trim());
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    if (date.isBefore(DateTime(1900)) || date.isAfter(today)) return null;
    return DateUtils.dateOnly(date);
  } on FormatException {
    return null;
  }
}

Future<AppCityOption?> showClientCitySelection({
  required BuildContext context,
  ClientService? service,
}) => showAppBottomSheet<AppCityOption>(
  context: context,
  title: 'Selecionar cidade',
  subtitle: 'Pesquise pelo nome da cidade ou pela UF.',
  icon: Icons.location_city_outlined,
  heightFactor: .76,
  builder: (_) => _CityPickerSheet(service: service ?? ClientService()),
);

class _CityPickerSheet extends StatefulWidget {
  final ClientService service;

  const _CityPickerSheet({required this.service});

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<AppCityOption> _cities = const [];
  bool _loading = false;
  String? _error;
  int _requestVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();
    if (query.length < 2) {
      _requestVersion++;
      setState(() {
        _cities = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _searchCities(query);
    });
  }

  Future<void> _searchCities(String query) async {
    final int request = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<AppCityOption> result = await widget.service.searchCities(
        query: query,
      );
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _cities = result;
        _loading = false;
      });
    } on ClientServiceException catch (error) {
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _cities = const [];
        _loading = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Digite cidade ou UF',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.colors.primary,
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar',
                        onPressed: () {
                          _search.clear();
                          _onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ),
      );
    }
    if (_cities.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().length < 2
              ? 'Digite ao menos dois caracteres.'
              : 'Nenhuma cidade encontrada.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _cities.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: context.colors.divider.withValues(alpha: .65),
      ),
      itemBuilder: (context, index) {
        final AppCityOption city = _cities[index];
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.location_on_outlined,
              color: context.colors.primary,
              size: 19,
            ),
            title: Text(
              city.displayName,
              style: const TextStyle(fontSize: 12.5),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 19),
            onTap: () => Navigator.pop(context, city),
          ),
        );
      },
    );
  }
}

class _CityField extends StatelessWidget {
  final AppCityOption? city;
  final bool enabled;
  final bool isRequired;
  final VoidCallback onTap;

  const _CityField({
    required this.city,
    required this.enabled,
    required this.isRequired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: _inputDecoration(
            context,
            isRequired ? 'Cidade *' : 'Cidade',
            Icons.location_city_outlined,
            suffix: const Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(
            city?.displayName.isNotEmpty == true
                ? city!.displayName
                : 'Não informada',
            style: TextStyle(
              fontSize: 13,
              color: city == null
                  ? context.colors.textPlaceholder
                  : context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticClientField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StaticClientField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: _inputDecoration(context, label, icon),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final AppClientContact contact;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactTile({
    required this.contact,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: context.colors.primary.withValues(alpha: 0.12),
        foregroundColor: context.colors.primary,
        child: const Icon(Icons.person_outline_rounded, size: 18),
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          contact.type,
          contact.phone == null ? null : formatBrazilianPhone(contact.phone),
        ].whereType<String>().where((value) => value.isNotEmpty).join(' • '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: canEdit
          ? PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            )
          : null,
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final AppClientDocument document;
  final bool canEdit;
  final Future<AppDownloadedDocument> Function() loadFile;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DocumentCard({
    required this.document,
    required this.canEdit,
    required this.loadFile,
    required this.onDownload,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.divider),
      ),
      child: InkWell(
        onTap: document.available ? onDownload : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: context.colors.background,
                    child: _DocumentPreview(
                      document: document,
                      loadFile: loadFile,
                    ),
                  ),
                  if (canEdit)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: _DocumentMenu(
                        onDownload: onDownload,
                        onEdit: onEdit,
                        onDelete: onDelete,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    document.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  final AppClientDocument document;
  final Future<AppDownloadedDocument> Function() loadFile;

  const _DocumentPreview({required this.document, required this.loadFile});

  @override
  Widget build(BuildContext context) {
    if (!document.available) {
      return _DocumentTypeIcon(
        icon: Icons.hide_source_rounded,
        color: context.colors.textSecondary,
      );
    }
    if (_isImageDocument(document)) {
      return FutureBuilder<AppDownloadedDocument>(
        future: loadFile(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _DocumentTypeIcon(
                icon: Icons.image_not_supported_outlined,
                color: context.colors.textSecondary,
              ),
            );
          }
          if (snapshot.hasError) {
            return _DocumentTypeIcon(
              icon: Icons.broken_image_outlined,
              color: context.colors.textSecondary,
            );
          }
          return Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.primary,
              ),
            ),
          );
        },
      );
    }
    if (_isPdfDocument(document)) {
      return const _DocumentTypeIcon(
        icon: Icons.picture_as_pdf_rounded,
        color: Color(0xffd32f2f),
      );
    }
    return _DocumentTypeIcon(
      icon: Icons.insert_drive_file_outlined,
      color: context.colors.primary,
    );
  }
}

class _DocumentTypeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _DocumentTypeIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(icon, color: color, size: 45));
}

class _DocumentMenu extends StatelessWidget {
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DocumentMenu({
    required this.onDownload,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Opções do documento',
    icon: const Icon(Icons.more_vert_rounded, size: 19),
    style: IconButton.styleFrom(
      backgroundColor: context.colors.surface.withValues(alpha: 0.9),
      minimumSize: const Size.square(30),
      padding: EdgeInsets.zero,
    ),
    onSelected: (value) {
      switch (value) {
        case 'download':
          onDownload();
          return;
        case 'edit':
          onEdit();
          return;
        case 'delete':
          onDelete();
          return;
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'download', child: Text('Baixar')),
      PopupMenuItem(value: 'edit', child: Text('Editar descrição')),
      PopupMenuItem(value: 'delete', child: Text('Excluir')),
    ],
  );
}

bool _isImageDocument(AppClientDocument document) {
  if (document.contentType?.toLowerCase().startsWith('image/') == true) {
    return true;
  }
  final String name = document.fileName.toLowerCase();
  return RegExp(r'\.(jpe?g|png|gif|webp|bmp|tiff?)$').hasMatch(name);
}

bool _isPdfDocument(AppClientDocument document) {
  return document.contentType?.toLowerCase() == 'application/pdf' ||
      document.fileName.toLowerCase().endsWith('.pdf');
}

class _EmptySection extends StatelessWidget {
  final String text;

  const _EmptySection({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
    ),
  );
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _DialogField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: CupertinoTextField(
      controller: controller,
      placeholder: hint,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      padding: const EdgeInsets.all(10),
    ),
  );
}

class _ClientContactDialog extends StatefulWidget {
  final AppClientContact? contact;

  const _ClientContactDialog({this.contact});

  @override
  State<_ClientContactDialog> createState() => _ClientContactDialogState();
}

class _ClientContactDialogState extends State<_ClientContactDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.contact?.name,
  );
  late final TextEditingController _phone = TextEditingController(
    text: formatBrazilianPhone(widget.contact?.phone),
  );
  late final TextEditingController _type = TextEditingController(
    text: widget.contact?.type,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.contact?.notes,
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _type.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: Text(widget.contact == null ? 'Novo contato' : 'Editar contato'),
    content: Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _DialogField(controller: _name, hint: 'Nome'),
            _DialogField(
              controller: _phone,
              hint: 'Telefone',
              keyboardType: TextInputType.phone,
              inputFormatters: const [BrazilianPhoneInputFormatter()],
            ),
            _DialogField(controller: _type, hint: 'Tipo/vínculo'),
            _DialogField(controller: _notes, hint: 'Observações'),
          ],
        ),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context, {
          'name': _name.text,
          'phone': _phone.text,
          'type': _type.text,
          'notes': _notes.text,
        }),
        child: const Text('Salvar'),
      ),
    ],
  );
}

class _ClientActionBar extends StatelessWidget {
  final Key? primaryKey;
  final bool canEdit;
  final bool saving;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;

  const _ClientActionBar({
    this.primaryKey,
    required this.canEdit,
    required this.saving,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
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
      child: Text(secondaryLabel),
    );
    final primaryButton = Container(
      key: primaryKey,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9FD995), Color(0xFF4B7D60)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FilledButton(
        onPressed: onPrimary,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: saving
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(primaryLabel),
      ),
    );

    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
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

InputDecoration _inputDecoration(
  BuildContext context,
  String label,
  IconData icon, {
  Widget? suffix,
}) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontSize: 12),
  prefixIcon: Icon(icon, size: 18, color: context.colors.primary),
  suffixIcon: suffix,
  filled: true,
  fillColor: context.colors.background,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: context.colors.divider),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: context.colors.divider),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: context.colors.primary, width: 1.4),
  ),
  disabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: context.colors.divider),
  ),
);

String? _nullableText(String value) {
  final String result = value.trim();
  return result.isEmpty ? null : result;
}

String _formatDateTime(DateTime? value) => value == null
    ? 'Não informado'
    : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

String? _legacyMapLink(AppClientDetail client) {
  final double? latitude = client.businessLatitude ?? client.latitude;
  final double? longitude = client.businessLongitude ?? client.longitude;
  if (latitude == null || longitude == null) return null;
  return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
}

Uri? _mapUri(String value) {
  final String normalized = value.trim();
  if (normalized.isEmpty) return null;
  final Uri? uri = Uri.tryParse(
    normalized.contains('://') ? normalized : 'https://$normalized',
  );
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _personTypeValue(String? value, String? document) {
  final String normalized = (value ?? '').trim().toUpperCase();
  if (normalized.startsWith('J') || normalized.contains('JURID')) {
    return 'JURIDICA';
  }
  if (normalized.startsWith('F') || normalized.contains('FISIC')) {
    return 'FISICA';
  }
  return _digits(document ?? '').length == 14 ? 'JURIDICA' : 'FISICA';
}

String _formatCpfCnpj(String value) {
  final String digits = _digits(value);
  if (digits.length <= 11) {
    final StringBuffer result = StringBuffer();
    for (int index = 0; index < digits.length; index++) {
      if (index == 3 || index == 6) result.write('.');
      if (index == 9) result.write('-');
      result.write(digits[index]);
    }
    return result.toString();
  }
  final String limited = digits.length > 14 ? digits.substring(0, 14) : digits;
  final StringBuffer result = StringBuffer();
  for (int index = 0; index < limited.length; index++) {
    if (index == 2 || index == 5) result.write('.');
    if (index == 8) result.write('/');
    if (index == 12) result.write('-');
    result.write(limited[index]);
  }
  return result.toString();
}

class _CpfCnpjInputFormatter extends TextInputFormatter {
  const _CpfCnpjInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = _digits(newValue.text);
    final String limited = digits.length > 14
        ? digits.substring(0, 14)
        : digits;
    final String formatted = _formatCpfCnpj(limited);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
    composing: TextRange.empty,
  );
}

bool _isValidCnpj(String value) {
  final String digits = _digits(value);
  if (digits.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(digits)) {
    return false;
  }
  int checkDigit(int length, List<int> weights) {
    int sum = 0;
    for (int index = 0; index < length; index++) {
      sum += int.parse(digits[index]) * weights[index];
    }
    final int remainder = sum % 11;
    return remainder < 2 ? 0 : 11 - remainder;
  }

  final int first = checkDigit(12, const [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  if (first != int.parse(digits[12])) return false;
  final int second = checkDigit(13, const [
    6,
    5,
    4,
    3,
    2,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
  ]);
  return second == int.parse(digits[13]);
}
