import 'package:flutter/material.dart';
import 'package:money/money.dart';
import 'package:url_launcher/url_launcher.dart';

class IosDownloadScreen extends StatefulWidget {
  const IosDownloadScreen({super.key});

  @override
  State<IosDownloadScreen> createState() => _IosDownloadScreenState();
}

class _IosDownloadScreenState extends State<IosDownloadScreen> {
  final AppUpdateService _updateService = AppUpdateService();

  AppUpdateRelease? _release;
  bool _loading = true;
  bool _opening = false;
  String? _errorMessage;

  bool get _available =>
      _release?.available == true && _release!.installUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadRelease();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SelectionArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double horizontalPadding = constraints.maxWidth < 420
                    ? 20
                    : 24;
                final double contentWidth =
                    (constraints.maxWidth - (horizontalPadding * 2))
                        .clamp(0, 620)
                        .toDouble();
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 32,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: 8),
                          Image.asset(
                            AppImages.money,
                            width: constraints.maxWidth < 420 ? 190 : 220,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 36),
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4E9),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Icon(
                              Icons.phone_iphone_rounded,
                              size: 46,
                              color: Color(0xFF4D914B),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Instale o Money no iPhone',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF1F2A1F),
                              fontSize: 30,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _release?.version.isNotEmpty == true
                                ? 'Versão ${_release!.version} • Distribuição privada Ad Hoc'
                                : 'Distribuição privada Ad Hoc',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF687268),
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 30),
                          const _InstallStep(
                            number: '1',
                            title: 'Abra pelo Safari',
                            description:
                                'Use esta página diretamente no iPhone que receberá o aplicativo.',
                          ),
                          const SizedBox(height: 12),
                          const _InstallStep(
                            number: '2',
                            title: 'Toque em instalar',
                            description:
                                'O iOS solicitará sua confirmação antes de iniciar o download.',
                          ),
                          const SizedBox(height: 12),
                          const _InstallStep(
                            number: '3',
                            title: 'Aguarde o ícone aparecer',
                            description:
                                'O aparelho precisa estar previamente cadastrado pelo UDID.',
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0xFF4D914B),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFFC8D7C8,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _available && !_opening
                                  ? _install
                                  : null,
                              child: _loading || _opening
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : const Text(
                                      'INSTALAR NO IPHONE',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                            ),
                          ),
                          if (!_loading && !_available) ...<Widget>[
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage ??
                                  'O instalador iOS será disponibilizado aqui após a publicação do IPA.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF8A5C2C),
                                fontSize: 13,
                              ),
                            ),
                            TextButton(
                              onPressed: _loadRelease,
                              child: const Text(
                                'VERIFICAR NOVAMENTE',
                                style: TextStyle(color: Color(0xFF4D914B)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F9F7),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE5EAE5),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: Color(0xFF4D914B),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Este instalador funciona somente em iPhones autorizados. As próximas atualizações serão avisadas dentro do próprio Money.',
                                    style: TextStyle(
                                      color: Color(0xFF596359),
                                      height: 1.4,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadRelease() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final AppUpdateManifest manifest = await _updateService.fetchManifest();
      if (!mounted) return;
      setState(() {
        _release = manifest.ios;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Não foi possível consultar o instalador. Verifique sua conexão.';
      });
    }
  }

  Future<void> _install() async {
    final String installUrl = _release?.installUrl ?? '';
    if (installUrl.isEmpty || _opening) return;
    setState(() {
      _opening = true;
      _errorMessage = null;
    });
    try {
      final bool opened = await launchUrl(
        Uri.parse(installUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Falha ao abrir o instalador.');
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Não foi possível abrir a instalação. Confirme que esta página está aberta no Safari.';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

class _InstallStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _InstallStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAE5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D1F2A1F),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF4D914B),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF263126),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF687268),
                    height: 1.35,
                    fontSize: 13,
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
