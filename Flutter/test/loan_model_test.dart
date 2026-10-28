import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('interpreta feedback herdado de contrato renovado', () {
    final AppLoanFeedback feedback = AppLoanFeedback.fromJson({
      'id': 17,
      'loanId': 49002,
      'text': 'Cliente solicitou retorno na sexta-feira.',
      'authorId': 3,
      'authorName': 'Administrador',
      'createdAt': '2026-09-29T10:30:00',
      'inheritedFromLoanId': 48991,
      'inherited': true,
    });

    expect(feedback.loanId, 49002);
    expect(feedback.authorName, 'Administrador');
    expect(feedback.inherited, isTrue);
    expect(feedback.inheritedFromLoanId, 48991);
  });

  test('página de empréstimos preserva valores e lucro do backend', () {
    final AppLoanPage page = AppLoanPage.fromJson({
      'items': [
        {
          'id': 38208,
          'clientName': 'Cliente Teste',
          'regionId': 33,
          'regionName': 'Região Central',
          'cityName': 'Cuiabá - MT',
          'nextDueDate': '2026-08-10T00:00:00',
          'status': 'Em atraso',
          'statusColor': '#FA8282',
          'receivableAmount': 1200.0,
          'receivedAmount': 300.0,
          'loanedAmount': 800.0,
          'profitAmount': 400.0,
          'paymentType': 'Mensal',
          'negotiated': false,
          'installmentProgress': '1/4',
        },
      ],
      'page': 0,
      'size': 50,
      'totalItems': 1,
      'totalPages': 1,
      'hasNext': false,
      'totals': {
        'loans': 1,
        'receivableAmount': 1200.0,
        'receivedAmount': 300.0,
        'profitAmount': 400.0,
        'loanedAmount': 800.0,
      },
    });

    expect(page.items, hasLength(1));
    expect(page.items.single.status, 'Em atraso');
    expect(page.items.single.profitAmount, 400);
    expect(page.totals.profitAmount, 400);
    expect(page.size, 50);
  });

  test('empréstimo sem valores financeiros inicia lucro em zero', () {
    final AppLoanSummary loan = AppLoanSummary.fromJson({
      'id': 12,
      'clientName': 'Cliente sem negociação',
      'regionId': 3,
      'regionName': 'Região Central',
      'status': 'Em dia',
      'statusColor': '#FFFFFF',
    });

    expect(loan.profitAmount, 0);
  });

  test('exibe PIX pendente em qualquer status do contrato', () {
    AppLoanSummary loan(String status, {required bool hasPendingPix}) =>
        AppLoanSummary.fromJson({
          'id': 13,
          'clientName': 'Cliente PIX',
          'regionId': 3,
          'regionName': 'Região Central',
          'status': status,
          'statusColor': '#FFFFFF',
          'hasPendingPix': hasPendingPix,
        });

    expect(loan('Vence hoje', hasPendingPix: true).showPendingPix, isTrue);
    expect(loan('Vence hoje', hasPendingPix: false).showPendingPix, isFalse);
    expect(loan('Em atraso', hasPendingPix: true).showPendingPix, isTrue);
    expect(loan('Em dia', hasPendingPix: true).showPendingPix, isTrue);
  });

  test('rodapé soma os visíveis e restringe lucro aos encerrados', () {
    AppLoanSummary loan({
      required int id,
      required String status,
      required double profit,
      required double receivable,
      required double received,
      required double loaned,
    }) => AppLoanSummary.fromJson({
      'id': id,
      'clientName': 'Cliente $id',
      'regionId': 3,
      'regionName': 'Região Central',
      'status': status,
      'statusColor': '#FFFFFF',
      'profitAmount': profit,
      'receivableAmount': receivable,
      'receivedAmount': received,
      'loanedAmount': loaned,
    });

    final AppLoanTotals totals = AppLoanTotals.fromVisibleLoans([
      loan(
        id: 1,
        status: 'Quitado',
        profit: 100,
        receivable: 10,
        received: 200,
        loaned: 500,
      ),
      loan(
        id: 2,
        status: 'Renov/Abat',
        profit: 200,
        receivable: 20,
        received: 300,
        loaned: 600,
      ),
      loan(
        id: 3,
        status: 'Em dia',
        profit: 900,
        receivable: 30,
        received: 400,
        loaned: 700,
      ),
    ]);

    expect(totals.loans, 3);
    expect(totals.receivableAmount, 60);
    expect(totals.receivedAmount, 900);
    expect(totals.loanedAmount, 1800);
    expect(totals.profitAmount, 300);
  });

  test('detalhe distingue valor original e negociado do refinanciamento', () {
    final AppLoanDetail detail = AppLoanDetail.fromJson({
      'id': 10,
      'clientId': 2,
      'clientName': 'CLIENTE TESTE',
      'regionId': 3,
      'regionName': 'REGIÃO TESTE',
      'paymentTypeCode': 'D',
      'paymentType': 'Diário',
      'loanedAmount': 1200,
      'originalLoanAmount': 500,
      'interestAmount': 0,
      'negotiatedAmount': 1200,
      'negotiatedOrigin': true,
    });

    expect(detail.loanedAmount, 1200);
    expect(detail.originalLoanAmount, 500);
    expect(detail.negotiatedAmount, 1200);
    expect(detail.negotiatedOrigin, isTrue);
  });

  test('contrato comum expõe juros legados como valor negociado', () {
    final AppLoanDetail detail = AppLoanDetail.fromJson({
      'id': 11,
      'clientId': 2,
      'clientName': 'CLIENTE TESTE',
      'regionId': 3,
      'regionName': 'REGIÃO TESTE',
      'paymentTypeCode': 'D',
      'paymentType': 'Diário',
      'loanedAmount': 500,
      'interestAmount': 1200,
      'totalAmount': 1700,
    });

    expect(detail.negotiatedAmount, 1200);
    expect(detail.totalAmount, 1700);
    expect(detail.negotiatedOrigin, isFalse);
  });

  test('pagamento parcela sugere o valor nominal calculado pelo contrato', () {
    final AppLoanDetail detail = AppLoanDetail.fromJson({
      'id': 12,
      'clientId': 2,
      'clientName': 'CLIENTE TESTE',
      'regionId': 3,
      'regionName': 'REGIÃO TESTE',
      'paymentTypeCode': 'D',
      'paymentType': 'Diário',
      'loanedAmount': 400,
      'interestAmount': 100,
      'discountAmount': 0,
      'installmentCount': 10,
      'installmentAmount': 50,
    });

    expect(suggestedInstallmentPaymentAmount(detail), 50);
  });

  test('pagamento parcela mantém compatibilidade com contratos legados', () {
    final AppLoanDetail detail = AppLoanDetail.fromJson({
      'id': 13,
      'clientId': 2,
      'clientName': 'CLIENTE TESTE',
      'regionId': 3,
      'regionName': 'REGIÃO TESTE',
      'paymentTypeCode': 'D',
      'paymentType': 'Diário',
      'loanedAmount': 300,
      'interestAmount': 60,
      'discountAmount': 10,
      'installmentCount': 7,
    });

    expect(suggestedInstallmentPaymentAmount(detail), 50);
  });

  test('conferência PIX preserva o valor da cobrança', () {
    final AppLoanApproval approval = AppLoanApproval.fromJson({
      'id': 19,
      'type': 'PIX',
      'status': 'AGUARDANDO',
      'description': 'Cobrança PIX do contrato',
      'amount': 700.0,
      'requester': 'SISTEMA',
    });

    expect(approval.amount, 700);
  });
}
