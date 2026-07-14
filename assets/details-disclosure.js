class DetailsDisclosure extends HTMLElement {
  constructor() {
    super();
    this.mainDetailsToggle = this.querySelector('details');
    this.content = this.mainDetailsToggle.querySelector('summary').nextElementSibling;

    this.mainDetailsToggle.addEventListener('focusout', this.onFocusOut.bind(this));
    this.mainDetailsToggle.addEventListener('toggle', this.onToggle.bind(this));
    this.onBodyClickEvent = this.onBodyClickEvent || this.onBodyClick.bind(this);
  }

  onBodyClick(event) {
    if (!this.contains(event.target)) {
      this.close();
    }
  }

  onFocusOut() {
    setTimeout(() => {
      if (!this.contains(document.activeElement)) {
        if (document.activeElement === document.body) return;
        this.close();
      }
    });
  }

  onToggle() {
    if (!this.animations) this.animations = this.content.getAnimations();

    if (this.mainDetailsToggle.hasAttribute('open')) {
      this.animations.forEach((animation) => animation.play());
      setTimeout(() => document.addEventListener('click', this.onBodyClickEvent));
    } else {
      this.animations.forEach((animation) => animation.cancel());
      document.removeEventListener('click', this.onBodyClickEvent);
    }
  }

  close() {
    this.mainDetailsToggle.removeAttribute('open');
    this.mainDetailsToggle.querySelector('summary').setAttribute('aria-expanded', false);
    document.removeEventListener('click', this.onBodyClickEvent);
  }
}

customElements.define('details-disclosure', DetailsDisclosure);

class HeaderMenu extends DetailsDisclosure {
  constructor() {
    super();
    this.header = document.querySelector('.header-wrapper');
  }

  onToggle() {
    if (!this.header) return;
    this.header.preventHide = this.mainDetailsToggle.open;

    if (document.documentElement.style.getPropertyValue('--header-bottom-position-desktop') !== '') return;
    document.documentElement.style.setProperty(
      '--header-bottom-position-desktop',
      `${Math.floor(this.header.getBoundingClientRect().bottom)}px`
    );
  }
}

customElements.define('header-menu', HeaderMenu);
