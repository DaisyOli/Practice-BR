import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="quiz-rescue"
//
// Guarda as respostas no navegador enquanto o aluno escreve. Se o envio falhar
// (banco fora do ar, queda de conexão), ele volta pro exercício e encontra tudo
// no lugar em vez de digitar a redação de novo.
//
// Cuida só do que é digitado ou escolhido: lacunas, redação e múltipla escolha.
// Ordenação e associação ficam de fora de propósito — o estado delas mora em
// campos ocultos, e devolver o valor sem devolver as peças na tela mandaria uma
// resposta diferente da que o aluno está vendo.
//
// No modo "clear" (página de resultados) o rascunho é descartado: chegar ali
// significa que o envio deu certo.
const MAX_AGE_MS = 24 * 60 * 60 * 1000
const SAVE_DELAY_MS = 400

export default class extends Controller {
  static targets = ["notice"]
  static values = {
    key: String,
    mode: { type: String, default: "save" }
  }

  connect() {
    if (this.modeValue === "clear") {
      this.forget()
      return
    }

    this.restore()

    this.boundScheduleSave = this.scheduleSave.bind(this)
    this.element.addEventListener("input", this.boundScheduleSave)
    this.element.addEventListener("change", this.boundScheduleSave)
  }

  disconnect() {
    if (this.boundScheduleSave) {
      this.element.removeEventListener("input", this.boundScheduleSave)
      this.element.removeEventListener("change", this.boundScheduleSave)
    }
    clearTimeout(this.saveTimer)
  }

  // Gravação ------------------------------------------------------------

  scheduleSave() {
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), SAVE_DELAY_MS)
  }

  save() {
    const answers = {}

    this.fields().forEach((field) => {
      if (field.type === "radio") {
        if (field.checked) answers[field.name] = field.value
      } else if (field.value.trim() !== "") {
        answers[field.name] = field.value
      }
    })

    if (Object.keys(answers).length === 0) {
      this.forget()
    } else {
      this.write({ savedAt: Date.now(), answers })
    }
  }

  // Recuperação ---------------------------------------------------------

  restore() {
    const draft = this.read()
    if (!draft) return

    let restored = 0

    this.fields().forEach((field) => {
      const saved = draft.answers[field.name]
      if (saved === undefined) return

      if (field.type === "radio") {
        if (field.value === saved) {
          field.checked = true
          restored++
        }
      } else {
        field.value = saved
        restored++
      }
    })

    if (restored > 0) this.announce()
  }

  announce() {
    if (!this.hasNoticeTarget) return
    this.noticeTarget.style.display = "flex"
  }

  dismiss() {
    if (this.hasNoticeTarget) this.noticeTarget.style.display = "none"
  }

  // Campos --------------------------------------------------------------

  fields() {
    return Array.from(this.element.querySelectorAll("input, textarea")).filter(
      (field) => field.name.startsWith("answers[") && field.type !== "hidden"
    )
  }

  // Armazenamento -------------------------------------------------------
  //
  // Tudo em try/catch: em aba anônima o localStorage levanta erro, e ficar sem
  // rascunho é bem melhor que quebrar o exercício inteiro.

  storageKey() {
    return `quiz-draft:${this.keyValue}`
  }

  read() {
    try {
      const raw = localStorage.getItem(this.storageKey())
      if (!raw) return null

      const draft = JSON.parse(raw)
      if (!draft || !draft.answers) return null

      if (Date.now() - draft.savedAt > MAX_AGE_MS) {
        this.forget()
        return null
      }

      return draft
    } catch (_error) {
      return null
    }
  }

  write(draft) {
    try {
      localStorage.setItem(this.storageKey(), JSON.stringify(draft))
    } catch (_error) {
      // Sem espaço ou sem permissão: seguir em silêncio.
    }
  }

  forget() {
    try {
      localStorage.removeItem(this.storageKey())
    } catch (_error) {
      // idem
    }
  }
}
