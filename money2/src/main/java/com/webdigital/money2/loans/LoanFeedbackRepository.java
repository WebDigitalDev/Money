package com.webdigital.money2.loans;

import com.webdigital.money2.shared.ApiException;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

@Repository
public class LoanFeedbackRepository {

    private final NamedParameterJdbcTemplate jdbc;

    public LoanFeedbackRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<LoanFeedbackResponse> list(long loanId) {
        return jdbc.query("""
                SELECT f.id, f.emprestimo_id, f.texto, f.usuario_id,
                       COALESCE(NULLIF(trim(concat_ws(' ', u.first_name, u.last_name)), ''),
                                NULLIF(trim(f.autor_username), ''), 'Usuário') AS autor,
                       f.dtcad, f.herdado_de_emprestimo_id
                FROM money2_emprestimo_feedbacks f
                LEFT JOIN users u ON u.id = f.usuario_id
                WHERE f.emprestimo_id = :loanId
                ORDER BY f.dtcad DESC, f.id DESC
                """, Map.of("loanId", loanId), (rs, row) -> new LoanFeedbackResponse(
                rs.getLong("id"),
                rs.getLong("emprestimo_id"),
                rs.getString("texto"),
                (Long) rs.getObject("usuario_id"),
                rs.getString("autor"),
                dateTime(rs.getTimestamp("dtcad")),
                (Long) rs.getObject("herdado_de_emprestimo_id")));
    }

    public long insert(long loanId, long userId, String username, String text) {
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO money2_emprestimo_feedbacks
                    (emprestimo_id, usuario_id, autor_username, texto, dtcad)
                VALUES (:loanId, :userId, :username, :text, NOW())
                """, new MapSqlParameterSource()
                .addValue("loanId", loanId)
                .addValue("userId", userId)
                .addValue("username", username)
                .addValue("text", text), key, new String[]{"id"});
        Number value = key.getKey();
        if (value == null) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "O feedback não foi registrado.");
        }
        return value.longValue();
    }

    public boolean belongsToLoan(long feedbackId, long loanId) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM money2_emprestimo_feedbacks
                WHERE id = :feedbackId AND emprestimo_id = :loanId
                """, Map.of("feedbackId", feedbackId, "loanId", loanId), Integer.class);
        return count != null && count > 0;
    }

    public void delete(long feedbackId) {
        jdbc.update("DELETE FROM money2_emprestimo_feedbacks WHERE id = :id",
                Map.of("id", feedbackId));
    }

    public void copyForRenewal(long originLoanId, long destinationLoanId) {
        jdbc.update("""
                INSERT INTO money2_emprestimo_feedbacks
                    (emprestimo_id, usuario_id, autor_username, texto,
                     herdado_de_emprestimo_id, feedback_origem_id, dtcad)
                SELECT :destinationId, f.usuario_id, f.autor_username, f.texto,
                       :originId, COALESCE(f.feedback_origem_id, f.id), f.dtcad
                FROM money2_emprestimo_feedbacks f
                WHERE f.emprestimo_id = :originId
                ON CONFLICT (emprestimo_id, feedback_origem_id) DO NOTHING
                """, Map.of("originId", originLoanId, "destinationId", destinationLoanId));
    }

    private static LocalDateTime dateTime(Timestamp value) {
        return value == null ? null : value.toLocalDateTime();
    }
}
