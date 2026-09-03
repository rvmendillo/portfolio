const root = document.documentElement;
const scenes = [...document.querySelectorAll('.scene')];
const layers = [...document.querySelectorAll('[data-depth]')];
const nav = document.querySelector('.nav-shell nav');
const menu = document.querySelector('.menu');
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

function updateViewport() {
  root.style.setProperty('--vh', `${window.innerHeight}px`);
}

function update() {
  const max = document.documentElement.scrollHeight - innerHeight;
  root.style.setProperty('--progress', `${max > 0 ? scrollY / max * 100 : 0}%`);
  if (!reduceMotion) layers.forEach(layer => {
    const scene = layer.closest('.scene');
    const distance = scene ? scrollY - scene.offsetTop : scrollY;
    const depth = Number(layer.dataset.depth || 0);
    layer.style.setProperty('--parallax', `${distance * depth}px`);
  });
  let active = scenes[0];
  for (const scene of scenes) if (Math.abs(scene.getBoundingClientRect().top) < innerHeight * .52) active = scene;
  document.querySelectorAll('.nav-shell nav a').forEach(link => link.classList.toggle('active', link.hash === `#${active.id}`));
}

menu.addEventListener('click', () => {
  const open = nav.classList.toggle('open');
  menu.setAttribute('aria-expanded', String(open));
});
nav.addEventListener('click', () => { nav.classList.remove('open'); menu.setAttribute('aria-expanded', 'false'); });
addEventListener('resize', () => { updateViewport(); update(); }, { passive: true });
addEventListener('scroll', update, { passive: true });
document.querySelector('#year').textContent = new Date().getFullYear();
updateViewport();
update();
