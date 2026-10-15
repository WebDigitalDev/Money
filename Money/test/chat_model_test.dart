import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('interpreta limite restante, modelo e velocidade da conta ChatGPT', () {
    final AppCodexConnection connection = AppCodexConnection.fromJson({
      'enabled': true,
      'available': true,
      'connected': true,
      'connecting': false,
      'usage': {
        'usedPercent': 63.5,
        'windowDurationMinutes': 10080,
        'resetsAtEpochSeconds': 1800500000,
        'limitName': 'ChatGPT',
      },
      'models': [
        {
          'id': 'gpt-5.4',
          'name': 'GPT-5.4',
          'defaultModel': true,
          'acceptsImages': true,
          'defaultServiceTier': 'standard',
          'serviceTiers': [
            {'id': 'standard', 'name': 'Padrão', 'description': ''},
            {'id': 'fast', 'name': 'Rápida', 'description': 'Mais rápida'},
          ],
        },
      ],
      'defaultModel': 'gpt-5.4',
      'defaultServiceTier': 'fast',
    });

    expect(connection.usage?.usedPercent, 63.5);
    expect(connection.usage?.remainingPercent, 36.5);
    expect(connection.usage?.remainingProgress, 0.365);
    expect(connection.usage?.windowDurationMinutes, 10080);
    expect(connection.usage?.resetsAt, isNotNull);
    expect(connection.models.single.acceptsImages, isTrue);
    expect(connection.models.single.preferredTier, 'fast');
    expect(connection.defaultModel, 'gpt-5.4');
    expect(connection.defaultServiceTier, 'fast');
  });

  test('interpreta o contexto detalhado de contrato retornado pelo money2', () {
    final AppChatResponse response = AppChatResponse.fromJson({
      'message': 'Contrato encontrado',
      'mode': 'CONTRACT_CONTEXT',
      'suggestions': const [],
      'clients': const [],
      'semanticSearch': true,
      'contract': {
        'loanId': 46409,
        'clientId': 91,
        'clientName': 'Cliente Teste',
        'regionId': 12,
        'regionName': 'Capitalize',
        'contractDate': '2026-07-01',
        'paymentType': 'Mensal',
        'installmentCount': 3,
        'paidInstallments': 1,
        'openInstallments': 2,
        'overdueInstallments': 0,
        'loanedAmount': 900,
        'totalAmount': 1050,
        'receivedAmount': 150,
        'receivableAmount': 900,
        'profitAmount': 0,
        'status': 'Em dia',
        'approvalStatus': 'APROVADO',
        'lastPaymentDate': '2026-08-15',
        'lastPaymentAmount': 150,
        'nextDueDate': '2026-09-01',
        'nextDueAmount': 200,
        'createdBy': 'operador',
        'history': [
          {
            'category': 'EMPRESTIMO',
            'operation': 'criarEmprestimo',
            'description': 'Novo contrato criado.',
            'username': 'operador',
            'occurredAt': '2026-07-01T10:00:00',
          },
        ],
      },
    });

    expect(response.mode, 'CONTRACT_CONTEXT');
    expect(response.semanticSearch, isTrue);
    expect(response.contract?.loanId, 46409);
    expect(response.contract?.clientName, 'Cliente Teste');
    expect(response.contract?.history.single.username, 'operador');
    expect(response.contract?.asLoan.loanId, 46409);
    expect(response.contract?.asLoan.amount, 900);
  });
}
