import { Controller } from "@hotwired/stimulus"
import { isAnswerEvent } from "answer_event"

// Mede até onde o aluno chega numa atividade (ponto 2.1, 17/11/2026). O
// servidor guarda uma linha por abertura da página (ActivityVisit).
//
// - O primeiro toque, tecla ou rolagem cria a linha. O robô do antivírus de
//   email abre a página, mas não faz nada disso.
// - Cada passo novo avisa o mais longe que a pessoa chegou. Voltar não avisa.
// - A primeira resposta de verdade (answer_event.js) avisa uma vez.
// - O envio é marcado pelo próprio servidor, pelo visit_token do formulário.
//
// Connects to data-controller="quiz-visit", junto com o quiz-progress, que
// dispara "quiz-progress:step" a cada troca de questão.
const HUMAN_EVENTS = ["pointerdown", "keydown", "touchstart", "wheel"]

export default class extends Controller {
  static values = { url: String, token: String }

  connect() {
    this.furthest = 1
    this.answered = false

    this.onHuman = this.onHuman.bind(this)
    this.onAnswer = this.onAnswer.bind(this)

    HUMAN_EVENTS.forEach((name) => window.addEventListener(name, this.onHuman, { passive: true, capture: true }))
    this.element.addEventListener("pointerdown", this.onAnswer)
    this.element.addEventListener("input", this.onAnswer)
  }

  disconnect() {
    this.removeHumanListeners()
    this.element.removeEventListener("pointerdown", this.onAnswer)
    this.element.removeEventListener("input", this.onAnswer)
  }

  onHuman() {
    this.removeHumanListeners()
    this.send()
  }

  // data-action="quiz-progress:step->quiz-visit#advance"
  advance(event) {
    const current = event.detail?.current || 1
    if (current <= this.furthest) return
    this.furthest = current
    this.send()
  }

  onAnswer(event) {
    if (this.answered || !isAnswerEvent(event)) return
    this.answered = true
    this.send()
  }

  removeHumanListeners() {
    HUMAN_EVENTS.forEach((name) => window.removeEventListener(name, this.onHuman, { capture: true }))
  }

  send() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    // keepalive: a pessoa pode tocar em "Voltar" e sair da página no mesmo instante.
    fetch(this.urlValue, {
      method: "POST",
      keepalive: true,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ token: this.tokenValue, step: this.furthest, answered: this.answered })
    }).catch(() => { /* medição não pode atrapalhar quem está usando */ })
  }
}
