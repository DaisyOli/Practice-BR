import { Controller } from "@hotwired/stimulus"

// Avisa o servidor quando há uma pessoa de verdade usando o teste: um toque, uma
// tecla ou uma rolagem. O robô do antivírus de email pede a página, mas não faz
// nada disso, e por isso o funil consegue separar os dois.
//
// Connects to data-controller="trial-signal"
// Sem o evento "scroll": o próprio tour rola a página sozinho, e isso contaria como
// pessoa. A rolagem de verdade aparece aqui como toque ou roda do mouse.
const HUMAN_EVENTS = ["pointerdown", "keydown", "touchstart", "wheel"]
const ANSWER_TARGETS = "input, textarea, select, button, label, [draggable='true'], [data-action]"

export default class extends Controller {
  static values = { url: String, pending: Array }

  connect() {
    this.sent = new Set()
    this.form = document.querySelector(".quiz-exercise-form")

    this.onHuman = this.onHuman.bind(this)
    this.onAnswer = this.onAnswer.bind(this)

    HUMAN_EVENTS.forEach((name) => window.addEventListener(name, this.onHuman, { passive: true, capture: true }))
    if (this.form) {
      this.form.addEventListener("pointerdown", this.onAnswer)
      this.form.addEventListener("input", this.onAnswer)
    }
  }

  disconnect() {
    this.removeHumanListeners()
    if (this.form) {
      this.form.removeEventListener("pointerdown", this.onAnswer)
      this.form.removeEventListener("input", this.onAnswer)
    }
  }

  onHuman() {
    this.removeHumanListeners()
    this.send("app")
    if (this.form) this.send("activity")
  }

  // Tocar num ponto vazio do formulário não é começar a responder.
  onAnswer(event) {
    if (event.type === "pointerdown" && !event.target.closest(ANSWER_TARGETS)) return
    if (event.target.closest("[type='submit']")) return
    this.send("answer")
  }

  removeHumanListeners() {
    HUMAN_EVENTS.forEach((name) => window.removeEventListener(name, this.onHuman, { capture: true }))
  }

  send(kind) {
    if (this.sent.has(kind) || !this.pendingValue.includes(kind)) return
    this.sent.add(kind)

    const token = document.querySelector("meta[name='csrf-token']")?.content
    // keepalive: a pessoa pode tocar num link e sair da página no mesmo instante.
    fetch(this.urlValue, {
      method: "POST",
      keepalive: true,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ kind })
    }).catch(() => { /* medição não pode atrapalhar quem está usando */ })
  }
}
