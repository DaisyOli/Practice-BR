import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toast"
//
// O flash chega por data values e aparece no connect(). O Stimulus chama
// connect() toda vez que o elemento entra na página — inclusive nas navegações
// do Turbo, que trocam o corpo do documento sem recarregar nada.
//
// O mecanismo anterior era um evento customizado registrado dentro de um
// handler de DOMContentLoaded, e quebrava em dois lugares: o evento era
// disparado ANTES do ouvinte existir (dispatchEvent é síncrono, então a
// mensagem morria no vazio), e DOMContentLoaded não dispara de novo em
// navegação Turbo. Não havia como uma mensagem chegar à tela.
export default class extends Controller {
  static values = {
    notice:   String,
    alert:    String,
    duration: { type: Number, default: 5000 }
  }

  static ACCENTS = {
    success: "var(--success)",
    error:   "var(--error)",
    warning: "var(--warning)",
    info:    "var(--info)"
  }

  static ICONS = {
    success: "bi bi-check-circle-fill",
    error:   "bi bi-exclamation-circle-fill",
    warning: "bi bi-exclamation-triangle-fill",
    info:    "bi bi-info-circle-fill"
  }

  connect() {
    if (this.noticeValue) this.show(this.noticeValue, "success")
    if (this.alertValue) this.show(this.alertValue, "error")
  }

  show(message, type = "info") {
    if (!message) return

    const toast = this.build(message, type)
    this.element.appendChild(toast)

    requestAnimationFrame(() => {
      toast.style.opacity = "1"
      toast.style.transform = "translateX(0)"
    })

    setTimeout(() => this.remove(toast), this.durationValue)
  }

  dismiss(event) {
    this.remove(event.target.closest("[data-toast]"))
  }

  // O app não usa mais Bootstrap — só os ícones bi-* sobreviveram à faxina.
  // Por isso o estilo vem dos tokens do design system, e não de classes
  // utilitárias que não existem mais.
  build(message, type) {
    const accent = this.constructor.ACCENTS[type] || this.constructor.ACCENTS.info
    const icon = this.constructor.ICONS[type] || this.constructor.ICONS.info

    const toast = document.createElement("div")
    toast.setAttribute("data-toast", "")
    toast.setAttribute("role", "alert")
    toast.setAttribute("aria-live", "assertive")
    toast.style.cssText = `
      display:flex; align-items:flex-start; gap:10px;
      background:var(--surface); color:var(--ink);
      border:1px solid var(--line); border-left:4px solid ${accent};
      border-radius:12px; padding:14px 16px;
      box-shadow:0 6px 20px rgba(0,0,0,0.10);
      font-family:'Plus Jakarta Sans',sans-serif; font-size:0.88rem; line-height:1.45;
      opacity:0; transform:translateX(12px); transition:opacity .25s ease, transform .25s ease;
    `

    const glyph = document.createElement("i")
    glyph.className = icon
    glyph.style.cssText = `color:${accent}; flex-shrink:0; margin-top:2px;`

    const text = document.createElement("div")
    text.style.flex = "1"
    text.textContent = message

    const close = document.createElement("button")
    close.type = "button"
    close.setAttribute("aria-label", "Fechar")
    close.dataset.action = "click->toast#dismiss"
    close.textContent = "×"
    close.style.cssText = `
      background:none; border:none; cursor:pointer; flex-shrink:0;
      color:var(--ink-faint); font-size:1.15rem; line-height:1; padding:0 2px;
    `

    toast.append(glyph, text, close)
    return toast
  }

  remove(toast) {
    if (!toast) return

    toast.style.opacity = "0"
    toast.style.transform = "translateX(12px)"
    setTimeout(() => toast.remove(), 250)
  }
}
