const { app, safeStorage } = require('electron')
const { exec } = require('child_process')

function checkGnomeKeyring() {
  return new Promise((resolve) => {
    exec('ps aux | grep gnome-keyring', (error, stdout) => {
      console.log('GNOME Keyring processes:', stdout)
      resolve(!error && stdout.includes('gnome-keyring-daemon'))
    })
  })
}

function checkLibsecret() {
  return new Promise((resolve) => {
    exec('secret-tool lookup service test key test', (error, stdout) => {
      console.log('Libsecret test result:', error ? 'Error' : 'Success', stdout)
      resolve(!error)
    })
  })
}

function safeDecrypt(encrypted) {
  try {
    return safeStorage.decryptString(encrypted);
  } catch (error) {
    console.error('Decryption error:', error.message);
    console.error('This often happens when the keyring environment has changed.');
    console.error('Make sure to run the app with the same keyring session used for encryption.');
    
    // You could implement a fallback here or prompt the user to re-enter credentials
    return null; // or throw a more descriptive error
  }
}

app.whenReady().then(async () => {
  console.log('Electron app ready')
  console.log('Process env PASSWORD_STORE:', process.env.PASSWORD_STORE)
  
  const gnomeKeyringRunning = await checkGnomeKeyring()
  console.log('GNOME Keyring running:', gnomeKeyringRunning)
  
  const libsecretWorking = await checkLibsecret()
  console.log('Libsecret working:', libsecretWorking)
  
  console.log('safeStorage available:', safeStorage.isEncryptionAvailable())
  
  // Test safeStorage encryption and decryption directly
  console.log('--------- safeStorage Direct Test ---------')
  try {
    // Try to encrypt a string regardless of isEncryptionAvailable result
    const testString = 'This is a test string'
    console.log(`Attempting to encrypt: "${testString}"`)
    
    const encrypted = safeStorage.encryptString(testString)
    console.log('Encryption successful:', encrypted.toString('hex').substring(0, 20) + '...')
    
    try {
      console.log('Attempting to decrypt...')
      const decrypted = safeDecrypt(encrypted)
      console.log('Decryption successful:', decrypted)
      console.log('Decryption test passed:', decrypted === testString)
    } catch (decryptError) {
      console.error('Decryption error:', decryptError.message)
      console.error('Decryption error details:', decryptError)
    }
  } catch (encryptError) {
    console.error('Encryption error:', encryptError.message)
    console.error('Encryption error details:', encryptError)
  }
  console.log('----------------------------------------')
  
  if (safeStorage.isEncryptionAvailable()) {
    console.log('Encryption is available')
    // Your encryption/decryption code here
  } else {
    console.log('Encryption is not available on this system')
    console.log('Environment variables:')
    console.log('DISPLAY:', process.env.DISPLAY)
    console.log('DBUS_SESSION_BUS_ADDRESS:', process.env.DBUS_SESSION_BUS_ADDRESS)
  }
})
