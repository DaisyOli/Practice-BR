// 🎯 DASHBOARD DO ESTUDANTE - JavaScript dedicado

// Ícones desenhados igual aos botões reais do navegador (SVG inline, sem biblioteca)
const ICON_IOS_SHARE = '<svg xmlns="http://www.w3.org/2000/svg" width="1.1em" height="1.1em" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:inline-block;vertical-align:-0.2em"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" x2="12" y1="2" y2="15"/></svg>'
const ICON_ANDROID_MENU = '<svg xmlns="http://www.w3.org/2000/svg" width="1.1em" height="1.1em" viewBox="0 0 24 24" fill="currentColor" style="display:inline-block;vertical-align:-0.2em"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>'

const TOUR_TEXTS = {
  fr: {
    skip:            'Passer',
    start:           'Commencer →',
    next:            'Suivant →',
    finish:          'Terminer ✓',
    first_visit:     '<strong>Bienvenue sur Practice-BR ! 👋</strong><br><br>Votre essai comprend 3 activités. On commence par celle-ci ? Quelques minutes suffisent.',
    later:           'Plus tard',
    written:         '✍️ Vos <strong>expressions écrites</strong>, corrigées par l\'IA, sont ici. Cliquez sur <strong>+</strong> pour les relire.',
    written_seen:    'Compris ✓',
    welcome:         '<strong>Bienvenue sur Practice-BR ! 👋</strong><br><br>Faisons un rapide tour de la plateforme.',
    metrics:         'Ici vous suivez vos progrès : jours consécutifs 🔥, activités terminées et votre dernière note.',
    continue:        'Votre prochaine activité suggérée apparaît ici. Cliquez pour commencer quand vous êtes prêt(e) !',
    levels:          'Explorez les activités organisées par niveau — du A1 au C1. Cliquez sur un niveau pour voir ce qui est disponible.',
    avatar:          'Votre menu se trouve ici — pour vous déconnecter ou voir vos informations.',
    install_android: `📲 <strong>Installez l'application !</strong><br><br>Appuyez sur le menu <strong>${ICON_ANDROID_MENU}</strong> de Chrome puis choisissez <strong>« Ajouter à l'écran d'accueil »</strong> pour un accès rapide.`,
    install_ios:     `📲 <strong>Installez l'application !</strong><br><br>Appuyez sur <strong>${ICON_IOS_SHARE}</strong> dans Safari puis choisissez <strong>« Sur l'écran d'accueil »</strong> pour un accès rapide.`
  },
  en: {
    skip:            'Skip',
    start:           'Start →',
    next:            'Next →',
    finish:          'Finish ✓',
    first_visit:     '<strong>Welcome to Practice-BR! 👋</strong><br><br>Your trial includes 3 activities. Shall we start with this one? It only takes a few minutes.',
    later:           'Later',
    written:         '✍️ Your <strong>written answers</strong>, corrected by AI, are here. Click <strong>+</strong> to read them again.',
    written_seen:    'Got it ✓',
    welcome:         '<strong>Welcome to Practice-BR! 👋</strong><br><br>Let\'s take a quick tour of the platform.',
    metrics:         'Track your progress here: study streak 🔥, completed activities and your latest score.',
    continue:        'Your next suggested activity appears here. Click to start when you\'re ready!',
    levels:          'Explore activities organised by level — from A1 to C1. Click any level to see what\'s available.',
    avatar:          'Your menu is up here — to sign out or view your account.',
    install_android: `📲 <strong>Install the app!</strong><br><br>Tap the <strong>${ICON_ANDROID_MENU}</strong> menu in Chrome and choose <strong>"Add to Home Screen"</strong> for quick access.`,
    install_ios:     `📲 <strong>Install the app!</strong><br><br>Tap <strong>${ICON_IOS_SHARE}</strong> in Safari and choose <strong>"Add to Home Screen"</strong> for quick access.`
  },
  pt: {
    skip:            'Pular',
    start:           'Começar →',
    next:            'Próximo →',
    finish:          'Concluir ✓',
    first_visit:     '<strong>Boas-vindas à Practice-BR! 👋</strong><br><br>Seu teste tem 3 atividades. Vamos começar por esta? Poucos minutos bastam.',
    later:           'Depois',
    written:         '✍️ Suas <strong>expressões escritas</strong>, corrigidas pela IA, ficam aqui. Clique no <strong>+</strong> para reler.',
    written_seen:    'Entendi ✓',
    welcome:         '<strong>Boas-vindas à Practice-BR! 👋</strong><br><br>Vamos fazer um tour rápido para você conhecer a plataforma.',
    metrics:         'Aqui você acompanha seu progresso: sequência de estudos 🔥, atividades concluídas e sua última nota.',
    continue:        'Sua próxima atividade sugerida aparece aqui. Clique para começar quando estiver pronto(a)!',
    levels:          'Explore atividades organizadas por nível — do A1 ao C1. Clique em qualquer nível para ver o que está disponível.',
    avatar:          'Seu menu fica aqui em cima — para sair da conta ou ver suas informações.',
    install_android: `📲 <strong>Instale o app!</strong><br><br>Toque no menu <strong>${ICON_ANDROID_MENU}</strong> do Chrome e escolha <strong>"Adicionar à tela inicial"</strong> para acesso rápido.`,
    install_ios:     `📲 <strong>Instale o app!</strong><br><br>Toque em <strong>${ICON_IOS_SHARE}</strong> no Safari e escolha <strong>"Adicionar à tela de início"</strong> para acesso rápido.`
  }
}

function detectLang() {
  const lang = (navigator.language || 'pt').toLowerCase()
  if (lang.startsWith('fr')) return 'fr'
  if (lang.startsWith('en')) return 'en'
  return 'pt'
}

function detectMobileOS() {
  if (window.matchMedia('(display-mode: standalone)').matches) return null
  const ua = navigator.userAgent
  if (/android/i.test(ua)) return 'android'
  if (/iPad|iPhone|iPod/.test(ua)) return 'ios'
  return null
}

function initOnboardingTour() {
  if (typeof Shepherd === 'undefined') return
  const root = document.getElementById('student-dashboard-root')
  if (!root) return

  const userId = root.dataset.userId
  if (!userId) return

  const t = TOUR_TEXTS[detectLang()]

  // Primeira visita de quem nunca praticou: um passo só, apontando para a
  // atividade escolhida. Antes era o tour inteiro (métricas zeradas, níveis,
  // menu) por cima do "Comece por aqui" — e as 3 pessoas reais de 12–13/10
  // entraram e saíram sem fazer nada. O tour completo fica para depois da
  // primeira atividade, quando métricas e expressões escritas já dizem algo.
  if (root.dataset.neverPracticed === 'true') {
    showFirstVisitStep(userId, t)
    return
  }

  const storageKey = `practicebr_tour_done_${userId}`
  const writtenKey = `practicebr_written_hint_${userId}`
  const hasWritten = root.dataset.hasWritten === 'true'

  // Quem já fez o tour e acabou de ganhar a primeira expressão escrita
  // corrigida: só o passo que mostra onde ela mora.
  if (safeGet(storageKey)) {
    if (hasWritten && !safeGet(writtenKey)) showWrittenHint(writtenKey, t)
    return
  }

  // No navegador do celular a rolagem suave desalinha o recorte iluminado do tour:
  // a barra de endereço encolhe durante a rolagem e muda a altura da tela.
  // Rolagem instantânea garante que o holofote seja calculado com a tela já parada.
  const mobileBrowser = detectMobileOS() !== null
  const tour = new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: {
      cancelIcon: { enabled: true },
      scrollTo: { behavior: mobileBrowser ? 'auto' : 'smooth', block: 'center' }
    }
  })

  tour.addStep({
    id: 'welcome',
    text: t.welcome,
    buttons: [
      { text: t.skip,  action: () => tour.cancel(), classes: 'shepherd-button-secondary' },
      { text: t.start, action: () => tour.next() }
    ]
  })

  if (document.querySelector('#tour-metrics')) {
    tour.addStep({
      id: 'metrics',
      attachTo: { element: '#tour-metrics', on: 'bottom' },
      text: t.metrics,
      buttons: [{ text: t.next, action: () => tour.next() }]
    })
  }

  if (document.querySelector('#tour-continue')) {
    tour.addStep({
      id: 'continue',
      attachTo: { element: '#tour-continue', on: 'right' },
      text: t.continue,
      buttons: [{ text: t.next, action: () => tour.next() }]
    })
  }

  if (document.querySelector('#tour-levels')) {
    tour.addStep({
      id: 'levels',
      attachTo: { element: '#tour-levels', on: 'top' },
      text: t.levels,
      buttons: [{ text: t.next, action: () => tour.next() }]
    })
  }

  const mobileOS = detectMobileOS()
  if (mobileOS) {
    tour.addStep({
      id: 'install',
      text: mobileOS === 'ios' ? t.install_ios : t.install_android,
      buttons: [{ text: t.next, action: () => tour.next() }]
    })
  }

  if (hasWritten && document.querySelector('#open-ended-section')) {
    tour.addStep({
      id: 'written',
      attachTo: { element: '#open-ended-section', on: 'top' },
      text: t.written,
      buttons: [{ text: t.next, action: () => tour.next() }]
    })
  }

  if (document.querySelector('#tour-avatar')) {
    tour.addStep({
      id: 'avatar',
      attachTo: { element: '#tour-avatar', on: 'bottom' },
      text: t.avatar,
      buttons: [{ text: t.finish, action: () => tour.complete() }]
    })
  }

  const done = () => {
    safeSet(storageKey)
    if (hasWritten) safeSet(writtenKey)
  }
  tour.on('complete', done)
  tour.on('cancel',   done)

  tour.start()
}

// localStorage pode lançar exceção (aba anônima do Safari, armazenamento
// bloqueado). Sem isto, o tour quebraria o resto do JavaScript da dashboard.
function safeGet(key) {
  try { return localStorage.getItem(key) } catch (e) { return null }
}

function safeSet(key) {
  try { localStorage.setItem(key, '1') } catch (e) { /* sem memória: tudo bem */ }
}

function newTour() {
  return new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: { cancelIcon: { enabled: true }, scrollTo: { behavior: 'auto', block: 'center' } }
  })
}

// O "Começar" do passo vai direto para a atividade do bloco — a mesma do
// botão que está iluminado logo atrás.
function showFirstVisitStep(userId, t) {
  const key = `practicebr_first_visit_done_${userId}`
  const block = document.getElementById('tour-start-here')
  if (!block || safeGet(key)) return

  const link = block.querySelector('a[href]')
  const tour = newTour()
  tour.addStep({
    id: 'first-visit',
    attachTo: { element: '#tour-start-here', on: 'bottom' },
    text: t.first_visit,
    buttons: [
      { text: t.later, action: () => tour.cancel(), classes: 'shepherd-button-secondary' },
      { text: t.start, action: () => { safeSet(key); if (link) window.location.href = link.href } }
    ]
  })
  tour.on('cancel', () => safeSet(key))
  tour.start()
}

function showWrittenHint(writtenKey, t) {
  if (!document.querySelector('#open-ended-section')) return

  const tour = newTour()
  tour.addStep({
    id: 'written',
    attachTo: { element: '#open-ended-section', on: 'top' },
    text: t.written,
    buttons: [{ text: t.written_seen, action: () => tour.complete() }]
  })
  tour.on('complete', () => safeSet(writtenKey))
  tour.on('cancel',   () => safeSet(writtenKey))
  tour.start()
}

document.addEventListener('DOMContentLoaded', function() {
  // Função principal de inicialização
  function initStudentDashboard() {
    // ✅ BOTÃO CARREGAR MAIS ATIVIDADES
    const loadMoreBtn = document.querySelector('.load-more-btn');
    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', function() {
        const level = this.dataset.level;
        const offset = parseInt(this.dataset.offset);
        const spinner = document.querySelector('.loading-spinner');

        // Mostrar loading
        this.style.display = 'none';
        spinner.classList.remove('hidden');

        // Fazer requisição
        const url = `/students/load_more?level=${level}&offset=${offset}&locale=pt`;

        fetch(url)
          .then(response => {
            return response.json();
          })
          .then(data => {
            // Inserir HTML
            const container = document.getElementById('activities-container');
            if (container) {
              container.insertAdjacentHTML('beforeend', data.html);
            }

            // Atualizar estado do botão
            spinner.classList.add('hidden');

            if (data.has_more) {
              this.dataset.offset = data.next_offset;
              this.innerHTML = `<i class="bi bi-plus-lg"></i> Carregar mais (${data.remaining} restantes)`;
              this.style.display = 'inline-block';
            } else {
              this.style.display = 'none';
            }
          })
          .catch(error => {
            console.error('Erro:', error);
            spinner.classList.add('hidden');
            this.style.display = 'inline-block';
          });
      });
    }

    // ✅ ANIMAÇÕES DAS BARRAS DE PROGRESSO
    const progressBars = document.querySelectorAll('.progress-fill');
    progressBars.forEach(bar => {
      const width = bar.style.width || bar.getAttribute('data-width');
      bar.style.width = '0%';
      
      setTimeout(() => {
        bar.style.width = width;
      }, 500);
    });
    
    // ✅ EFEITO HOVER NOS CARDS
    const metricCards = document.querySelectorAll('.card-metrica');
    metricCards.forEach(card => {
      card.addEventListener('mouseenter', function() {
        this.style.transform = 'scale(1.05) translateY(-5px)';
      });
      
      card.addEventListener('mouseleave', function() {
        this.style.transform = 'scale(1) translateY(0)';
      });
    });
    
  }
  
  // Executar imediatamente se DOM já carregou
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initStudentDashboard);
  } else {
    initStudentDashboard();
  }
});

// ✅ COMPATIBILIDADE COM TURBO (Rails)
document.addEventListener('turbo:load', function() {
  // Pequeno delay para garantir que DOM está pronto
  setTimeout(() => {
    const loadMoreBtn = document.querySelector('.load-more-btn');
    if (loadMoreBtn && !loadMoreBtn.hasAttribute('data-js-attached')) {
      loadMoreBtn.setAttribute('data-js-attached', 'true');

      loadMoreBtn.addEventListener('click', function() {
        
        const level = this.dataset.level;
        const offset = parseInt(this.dataset.offset);
        const spinner = document.querySelector('.loading-spinner');
        
        this.style.display = 'none';
        spinner.classList.remove('hidden');
        
        fetch(`/students/load_more?level=${level}&offset=${offset}&locale=pt`)
          .then(r => r.json())
          .then(data => {
            document.getElementById('activities-container').insertAdjacentHTML('beforeend', data.html);
            spinner.classList.add('hidden');
            
            if (data.has_more) {
              this.dataset.offset = data.next_offset;
              this.innerHTML = `<i class="bi bi-plus-lg"></i> Carregar mais (${data.remaining} restantes)`;
              this.style.display = 'inline-block';
            } else {
              this.style.display = 'none';
            }
          })
          .catch(error => {
            console.error('Erro:', error);
            spinner.classList.add('hidden');
            this.style.display = 'inline-block';
          });
      });
    }
  }, 100);

  initOnboardingTour()
}); 