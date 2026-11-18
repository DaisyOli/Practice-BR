// O que conta como "começou a responder": mexer num exercício. Isso inclui
// escrever, escolher uma opção, arrastar uma palavra, ligar colunas e gravar
// áudio. Navegar ("Próxima", "Anterior", "Voltar"), fechar um aviso e enviar
// não contam.
//
// Até 17/11/2026, a regra olhava o formulário inteiro. Como "Próxima" e
// "Anterior" ficam dentro dele, avançar pelas questões contava como resposta
// (ponto 2.1). Agora só vale o que acontece dentro de um exercício
// (.question-card).
//
// Usada pelos sinais do teste (trial_signal) e pela medição de até onde a
// pessoa chegou (quiz_visit).
const ANSWER_TARGETS = [
  "input", "textarea", "select", "button", "label", "[draggable='true']", "[data-action]",
  ".draggable-word", ".draggable-sentence", ".matching-item"
].join(", ")

export function isAnswerEvent(event) {
  const target = event.target
  if (!(target instanceof Element)) return false
  if (!target.closest(".question-card")) return false
  if (target.closest("[type='submit']")) return false
  // Tocar no enunciado ou num espaço vazio do cartão não é responder.
  if (event.type === "pointerdown" && !target.closest(ANSWER_TARGETS)) return false
  return true
}
