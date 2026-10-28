import 'package:flutter/material.dart';
import 'package:money/core/core.dart';
import 'package:money/presentation/widgets/home/home_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  static final Uri _developerWebsite = Uri.parse('https://webdigital.dev');

  final String? version;

  const AboutScreen({super.key, this.version});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HomeAppBar(
        title: context.tr!.about_app(context.tr!.app_name),
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = AppDimensions.padding;
          final verticalPadding = AppDimensions.padding * 2;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (verticalPadding * 2),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Transform.translate(
                          offset: const Offset(0, -44),
                          child: Image.asset(
                            AppImages.money,
                            width: MediaQuery.of(context).size.width * 0.72,
                          ),
                        ),
                      ),
                      const SizedBox(height: 35),
                      Text(
                        context.tr!.about_app(context.tr!.app_name),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        context.tr!.about_app_description_1(
                          context.tr!.app_name,
                        ),
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.tr!.about_app_description_2(
                          context.tr!.app_name,
                        ),
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.tr!.about_app_description_3,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: Column(
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  context.tr!.powered_by,
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(width: 4),
                                Semantics(
                                  link: true,
                                  child: InkWell(
                                    onTap: () => launchUrl(
                                      _developerWebsite,
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Text(
                                      'WebDigital Developer',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor: context.colors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (version != null)
                              Text(
                                context.tr!.version(version!),
                                style: const TextStyle(fontSize: 15),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
