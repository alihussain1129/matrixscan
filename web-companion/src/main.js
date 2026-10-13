import { BrowserMultiFormatReader } from '@zxing/browser'
import { BarcodeFormat } from '@zxing/library'
import './style.css'

const reader = new BrowserMultiFormatReader()
const video = document.querySelector('#camera-preview')
const cameraStage = document.querySelector('#camera-stage')
const cameraPlaceholder = document.querySelector('#camera-placeholder')
const cameraButton = document.querySelector('#camera-button')
const cameraIndicator = document.querySelector('#camera-indicator')
const statusMessage = document.querySelector('#status-message')
const imageInput = document.querySelector('#image-input')
const resultTitle = document.querySelector('#result-title')
const resultContent = document.querySelector('#result-content')
const resultActions = document.querySelector('#result-actions')
const copyButton = document.querySelector('#copy-button')
const scanAgainButton = document.querySelector('#scan-again-button')
const historyList = document.querySelector('#history-list')
const clearHistoryButton = document.querySelector('#clear-history-button')

let cameraControls
let latestValue = ''
let sessionScans = []

function setStatus(message, state = '') {
  statusMessage.textContent = message
  statusMessage.dataset.state = state
}

function stopCamera() {
  cameraControls?.stop()
  cameraControls = undefined

  if (video.srcObject instanceof MediaStream) {
    video.srcObject.getTracks().forEach((track) => track.stop())
    video.srcObject = null
  }

  cameraPlaceholder.hidden = false
  cameraStage.classList.remove('is-active')
  cameraIndicator.classList.remove('is-active')
  cameraIndicator.innerHTML = '<span></span> Camera off'
  cameraButton.textContent = '◎ Start camera'
}

function renderHistory() {
  historyList.replaceChildren()
  clearHistoryButton.hidden = sessionScans.length === 0

  if (!sessionScans.length) {
    const empty = document.createElement('li')
    empty.className = 'history-empty'
    empty.textContent = 'Your recent scans will appear here.'
    historyList.append(empty)
    return
  }

  sessionScans.forEach((scan) => {
    const item = document.createElement('li')
    const type = document.createElement('span')
    const value = document.createElement('span')
    type.className = 'history-type'
    type.textContent = scan.format
    value.className = 'history-value'
    value.textContent = scan.value
    item.append(type, value)
    historyList.append(item)
  })
}

function showResult(result, source) {
  latestValue = result.getText()
  const format = (BarcodeFormat[result.getBarcodeFormat()] ?? 'BARCODE')
    .replaceAll('_', ' ')
    .toLowerCase()
    .replace(/\b\w/g, (letter) => letter.toUpperCase())

  resultTitle.textContent = format
  resultContent.replaceChildren()

  const value = document.createElement('p')
  value.className = 'result-value'
  value.textContent = latestValue
  resultContent.append(value)
  resultActions.hidden = false

  sessionScans = [{ format, value: latestValue, source }, ...sessionScans].slice(0, 5)
  renderHistory()
  setStatus(`Found a ${format} code. Your result is ready.`, 'success')
}

async function startCamera() {
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    setStatus('Camera access needs a secure HTTPS connection. You can scan an image instead.', 'error')
    return
  }

  cameraButton.disabled = true
  setStatus('Requesting camera access…')

  try {
    cameraControls = await reader.decodeFromConstraints(
      { audio: false, video: { facingMode: { ideal: 'environment' } } },
      video,
      (result) => {
        if (!result) return
        showResult(result, 'Camera')
        stopCamera()
      },
    )
    cameraPlaceholder.hidden = true
    cameraStage.classList.add('is-active')
    cameraIndicator.classList.add('is-active')
    cameraIndicator.innerHTML = '<span></span> Camera on'
    cameraButton.textContent = 'Stop camera'
    setStatus('Camera is ready. Hold a code inside the frame.')
  } catch (error) {
    const message = error instanceof Error ? error.message : 'The browser could not start your camera.'
    setStatus(`${message} Check the browser permission and try again, or scan an image.`, 'error')
    stopCamera()
  } finally {
    cameraButton.disabled = false
  }
}

async function scanImage(file) {
  if (!file) return

  stopCamera()
  resultTitle.textContent = 'Reading image…'
  setStatus('Scanning the selected image…')

  const imageUrl = URL.createObjectURL(file)
  try {
    const result = await reader.decodeFromImageUrl(imageUrl)
    showResult(result, 'Image')
  } catch (error) {
    const message = error instanceof Error ? error.message : 'No supported code was found.'
    resultTitle.textContent = 'No code found'
    setStatus(`Could not read a code from this image. ${message}`, 'error')
  } finally {
    URL.revokeObjectURL(imageUrl)
    imageInput.value = ''
  }
}

cameraButton.addEventListener('click', () => {
  if (cameraControls) {
    stopCamera()
    setStatus('Camera stopped. Start it again whenever you are ready.')
  } else {
    void startCamera()
  }
})

imageInput.addEventListener('change', (event) => {
  void scanImage(event.currentTarget.files?.[0])
})

copyButton.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(latestValue)
    setStatus('Result copied to your clipboard.', 'success')
  } catch {
    setStatus('Clipboard access is unavailable. Select and copy the result manually.', 'error')
  }
})

scanAgainButton.addEventListener('click', () => {
  latestValue = ''
  resultTitle.textContent = 'Ready when you are'
  resultContent.replaceChildren()
  const mark = document.createElement('div')
  const message = document.createElement('p')
  mark.className = 'empty-mark'
  mark.setAttribute('aria-hidden', 'true')
  mark.textContent = 'E'
  message.textContent = 'Scan a code to see its contents here.'
  resultContent.append(mark, message)
  resultActions.hidden = true
  setStatus('Start the camera, or choose an image to scan.')
})

clearHistoryButton.addEventListener('click', () => {
  sessionScans = []
  renderHistory()
})

window.addEventListener('pagehide', stopCamera)
renderHistory()
