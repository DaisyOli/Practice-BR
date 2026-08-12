import { Controller } from "@hotwired/stimulus"

// Editor dos prompts das IAs.
//
// Faz três coisas, todas por um motivo: um prompt é texto longo, e texto longo
// perdido dói muito mais que um campo de formulário perdido.
//
//   1. conta caracteres e linhas — dá noção de tamanho sem precisar rolar
//   2. avisa quando há alteração não salva
//   3. segura a saída da página se essa alteração existir
//
// O `disconnect()` não é enfeite: o Turbo troca a página sem recarregar o
// navegador, então um listener de `beforeunload` registrado aqui sobreviveria à
// navegação e passaria a barrar a saída de OUTRAS telas. Foi um parente desse
// bug que deixou o toast deste app mudo por um mês.
export default class extends Controller {
  static targets = ["body", "counter", "dirty"]
  static values  = { default: String }

  connect() {
    this.saved = this.bodyTarget.value
    this.guard = (event) => {
      if (!this.isDirty) return
      event.preventDefault()
      event.returnValue = ""
    }

    window.addEventListener("beforeunload", this.guard)
    this.update()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.guard)
  }

  get isDirty() {
    return this.bodyTarget.value !== this.saved
  }

  update() {
    const text  = this.bodyTarget.value
    const lines = text ? text.split("\n").length : 0

    let resumo = `${text.length} caracteres · ${lines} linha${lines === 1 ? "" : "s"}`

    // Útil quando ela está desfazendo à mão: avisa no instante em que o texto
    // volta a ser byte a byte o original, sem precisar salvar pra descobrir.
    if (this.hasDefaultValue && text === this.defaultValue) {
      resumo += " · igual ao original"
    }

    this.counterTarget.textContent = resumo

    if (this.hasDirtyTarget) {
      this.dirtyTarget.style.display = this.isDirty ? "inline" : "none"
    }
  }
}
