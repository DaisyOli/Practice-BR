import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="quiz-progress"
export default class extends Controller {
  static targets = ["bar", "counter", "question", "nextBtn", "prevBtn", "backBtn", "submitBtn", "materialPanel", "materialToggle"]
  static values = {
    total: Number,
    current: { type: Number, default: 1 }
  }

  connect() {
    // Mobile: manter o material visível por padrão para alunos de língua
    if (window.innerWidth < 768 && this.hasMaterialPanelTarget) {
      this.materialPanelTarget.classList.remove('collapsed')
      this.updateToggleLabel()
    }

    this.sizeStack()
    this.boundSizeStack = this.sizeStack.bind(this)
    window.addEventListener('resize', this.boundSizeStack)
    this.updateQuestionsVisibility()
    this.updateProgress()
    this.updateNavigation()
  }

  sizeStack() {
    // No mobile a página rola naturalmente — sem altura fixa no stack
    if (window.innerWidth < 768) return

    const outer = document.querySelector('.quiz-outer')
    const stack = this.element.querySelector('.quiz-questions-stack')
    if (!outer || !stack) return

    const navRow = this.element.querySelector('.quiz-nav-row')
    const navH = navRow
      ? navRow.offsetHeight + (parseFloat(window.getComputedStyle(navRow).marginTop) || 0)
      : 54

    const maxH = outer.getBoundingClientRect().bottom - stack.getBoundingClientRect().top - navH - 30
    if (maxH > 80) stack.style.maxHeight = maxH + 'px'
  }

  updateProgress() {
    if (this.hasBarTarget) {
      const percentage = (this.currentValue / this.totalValue) * 100
      this.barTarget.style.width = `${percentage}%`
    }

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.currentValue} de ${this.totalValue}`
    }
  }

  updateQuestionsVisibility() {
    if (this.hasQuestionTarget) {
      this.questionTargets.forEach((question, index) => {
        question.style.display = index === this.currentValue - 1 ? 'block' : 'none'
      })
    }
  }

  updateNavigation() {
    const isFirst = this.currentValue <= 1
    const isLast = this.currentValue >= this.totalValue

    if (this.hasBackBtnTarget) {
      this.backBtnTarget.style.display = isFirst ? 'flex' : 'none'
    }

    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.style.display = isFirst ? 'none' : 'flex'
    }

    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.style.display = isLast ? 'none' : 'flex'
    }

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.style.display = isLast ? 'block' : 'none'
    }
  }

  next() {
    if (this.currentValue < this.totalValue) {
      this.currentValue++
      this.updateAll()
      this.scrollToTop()
    }
  }

  previous() {
    if (this.currentValue > 1) {
      this.currentValue--
      this.updateAll()
      this.scrollToTop()
    }
  }

  goToQuestion(event) {
    const questionNumber = parseInt(event.target.dataset.questionNumber)
    if (questionNumber >= 1 && questionNumber <= this.totalValue) {
      this.currentValue = questionNumber
      this.updateAll()
      this.scrollToTop()
    }
  }

  updateAll() {
    this.updateProgress()
    this.updateQuestionsVisibility()
    this.updateNavigation()
    // A medição (quiz_visit_controller) escuta: até onde a pessoa chegou.
    this.dispatch("step", { detail: { current: this.currentValue } })
  }

  scrollToTop() {
    if (window.innerWidth < 768) {
      // No mobile, não rolar para o topo. Em vez disso, garantir que a questão ativa esteja visível.
      if (this.hasQuestionTarget) {
        const active = this.questionTargets[this.currentValue - 1]
        if (active) {
          active.scrollIntoView({ behavior: 'smooth', block: 'center' })
          return
        }
      }
      return
    }
    const stack = this.element.querySelector('.quiz-questions-stack')
    if (stack) stack.scrollTo({ top: 0, behavior: 'smooth' })
    else window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  toggleMaterial() {
    if (this.hasMaterialPanelTarget) {
      this.materialPanelTarget.classList.toggle('collapsed')
      this.updateToggleLabel()
    }
  }

  updateToggleLabel() {
    if (!this.hasMaterialToggleTarget) return
    const isCollapsed = this.hasMaterialPanelTarget &&
                        this.materialPanelTarget.classList.contains('collapsed')
    const btn = this.materialToggleTarget
    const showText = btn.dataset.textShow || 'Ver material de apoio'
    const hideText = btn.dataset.textHide || 'Ocultar material de apoio'
    btn.innerHTML = isCollapsed
      ? `<i class="bi bi-book"></i> ${showText} <i class="bi bi-chevron-down" style="margin-left:auto;"></i>`
      : `<i class="bi bi-book"></i> ${hideText} <i class="bi bi-chevron-up" style="margin-left:auto;"></i>`
  }

  handleKeydown(event) {
    if (event.key === 'ArrowRight' && !event.ctrlKey) {
      event.preventDefault()
      this.next()
    } else if (event.key === 'ArrowLeft' && !event.ctrlKey) {
      event.preventDefault()
      this.previous()
    }
  }

  disconnect() {
    window.removeEventListener('resize', this.boundSizeStack)
  }
}
