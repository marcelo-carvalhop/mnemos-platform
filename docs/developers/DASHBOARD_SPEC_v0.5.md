# Dashboard metodológico v0.5

O dashboard existe somente em app/web. A Home do aplicativo não deve incorporar essas métricas; Estatísticas/Dashboard é uma superfície própria. O firmware fornece `mnemos.metrics/v1` e mantém o histórico necessário para recomputação.

Os indicadores de referência são: retenção realizada em 30 dias; retenção semanal comparada à meta; sobreconfiança (erro com confiança >=70); consistência diária sem streak punitivo; maturidade (novo, aprendendo, jovem, maduro); carga prevista dos próximos 30 dias; retenção por deck; distribuição de D em dez bins. Tempo médio de resposta é coletado como sinal complementar. O Índice de Prontidão é opcional e corresponde, nesta versão, à média simples de retenção, calibração invertida e consistência normalizada.

Por padrão, retenção e calibração usam apenas eventos `sessionMode=review` e `affectsSchedule=true`. Prática voluntária pode ser mostrada separadamente como atividade, mas não deve inflar retenção programada. Toda métrica deve ser reproduzível a partir do histórico bruto; caches são permitidos apenas como otimização.
