import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toast"
export default class extends Controller {
  static targets = ["container"]
  static values = { 
    type: String,
    message: String,
    duration: { type: Number, default: 5000 },
    position: { type: String, default: "top-end" }
  }

  connect() {
    // Se existe mensagem nos values, mostra automaticamente
    if (this.hasMessageValue && this.messageValue) {
      this.show(this.messageValue, this.typeValue)
    }
  }

  // Método principal para mostrar toast
  show(message = null, type = "info") {
    const toastMessage = message || this.messageValue || "Notificação"
    const toastType = type || this.typeValue || "info"
    
    const toast = this.createToast(toastMessage, toastType)
    this.appendToContainer(toast)
    
    // Auto-remove após duração especificada
    setTimeout(() => {
      this.remove(toast)
    }, this.durationValue)
  }

  // Cria o elemento HTML do toast
  createToast(message, type) {
    const toast = document.createElement('div')
    toast.className = `toast align-items-center text-white bg-${this.getBootstrapType(type)} border-0 mb-2`
    toast.setAttribute('role', 'alert')
    toast.setAttribute('aria-live', 'assertive')
    toast.setAttribute('aria-atomic', 'true')
    
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">
          <i class="${this.getIcon(type)} me-2"></i>
          ${message}
        </div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-action="click->toast#dismiss" aria-label="Close"></button>
      </div>
    `
    
    return toast
  }

  // Adiciona o toast ao container
  appendToContainer(toast) {
    let container = this.getOrCreateContainer()
    container.appendChild(toast)
    
    // Trigger de entrada com animação
    setTimeout(() => {
      toast.classList.add('show')
    }, 100)
  }

  // Obtém ou cria o container de toasts
  getOrCreateContainer() {
    if (this.hasContainerTarget) {
      return this.containerTarget
    }
    
    // Cria container se não existir
    let container = document.getElementById('toast-container')
    if (!container) {
      container = document.createElement('div')
      container.id = 'toast-container'
      container.className = `toast-container position-fixed p-3 ${this.getPositionClasses()}`
      container.style.zIndex = '1050'
      document.body.appendChild(container)
    }
    
    return container
  }

  // Remove um toast específico
  remove(toast) {
    if (toast && toast.parentNode) {
      toast.classList.remove('show')
      setTimeout(() => {
        toast.remove()
      }, 300) // Espera a animação de saída
    }
  }

  // Action para dismissar via botão
  dismiss(event) {
    const toast = event.target.closest('.toast')
    this.remove(toast)
  }

  // Converte tipos para classes Bootstrap
  getBootstrapType(type) {
    const typeMap = {
      'success': 'success',
      'error': 'danger',
      'warning': 'warning',
      'info': 'info',
      'danger': 'danger'
    }
    return typeMap[type] || 'info'
  }

  // Retorna ícone apropriado para cada tipo
  getIcon(type) {
    const iconMap = {
      'success': 'bi bi-check-circle-fill',
      'error': 'bi bi-exclamation-circle-fill',
      'warning': 'bi bi-exclamation-triangle-fill',
      'info': 'bi bi-info-circle-fill',
      'danger': 'bi bi-exclamation-circle-fill'
    }
    return iconMap[type] || 'bi bi-info-circle-fill'
  }

  // Classes CSS para posicionamento
  getPositionClasses() {
    const positionMap = {
      'top-start': 'top-0 start-0',
      'top-center': 'top-0 start-50 translate-middle-x',
      'top-end': 'top-0 end-0',
      'middle-start': 'top-50 start-0 translate-middle-y',
      'middle-center': 'top-50 start-50 translate-middle',
      'middle-end': 'top-50 end-0 translate-middle-y',
      'bottom-start': 'bottom-0 start-0',
      'bottom-center': 'bottom-0 start-50 translate-middle-x',
      'bottom-end': 'bottom-0 end-0'
    }
    return positionMap[this.positionValue] || positionMap['top-end']
  }

  // Métodos de conveniência para diferentes tipos
  showSuccess(message) {
    this.show(message, 'success')
  }

  showError(message) {
    this.show(message, 'error')
  }

  showWarning(message) {
    this.show(message, 'warning')
  }

  showInfo(message) {
    this.show(message, 'info')
  }

  disconnect() {
  }
} 