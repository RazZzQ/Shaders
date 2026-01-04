using UnityEngine;

public class GlitchController : MonoBehaviour
{
    [Header("Configuración de Glitch")]
    [Range(0f, 1f)] public float glitchProbability; // probabilidad por segundo
    [SerializeField] private float glitchMinDuration;
    [SerializeField] private float glitchMaxDuration;
    [SerializeField] private float glitchCooldown; // tiempo mínimo entre glitches

    [Header("Referencia al Material")]
    [SerializeField] private  Material glitchMaterial;

    [Header("Estado interno (solo lectura)")]
    [SerializeField] private bool glitchActive = false;
    private float glitchTimer = 0f;
    private float cooldownTimer = 0f;

    void Update()
    {
        float dt = Time.deltaTime;

        //Control de tiempos
        if (glitchActive)
        {
            glitchTimer -= dt;

            if (glitchTimer <= 0f)
            {
                // Desactivar glitch
                glitchActive = false;
                glitchMaterial.SetFloat("_GlitchActive", 0f);
                glitchMaterial.SetFloat("_ChannelOffset", 0.1f);
                glitchMaterial.SetFloat("_GlitchAmount", 0.015f);
                glitchMaterial.SetFloat("_GlitchSpeed", 0.15f);
                cooldownTimer = glitchCooldown; // iniciar enfriamiento
            }
        }
        else
        {
            //Esperar cooldown antes de volver a activar
            if (cooldownTimer > 0f)
            {
                cooldownTimer -= dt;
            }
            else
            {
                //Chequear probabilidad solo una vez por frame
                if (Random.value < glitchProbability * dt)
                {
                    ActivateGlitch();
                }
            }
        }
    }

    void ActivateGlitch()
    {
        glitchActive = true;

        // Duración aleatoria
        glitchTimer = Random.Range(glitchMinDuration, glitchMaxDuration);

        // Interpolación aleatoria de GlitchAmount
        float[] possibleAmounts = { 0.015f, 0.02f, 0.03f };
        float randomGlitchAmount = possibleAmounts[Random.Range(0, possibleAmounts.Length)];

        //Aplicar al shader
        glitchMaterial.SetFloat("_GlitchActive", 1f);
        glitchMaterial.SetFloat("_ChannelOffset", 0.2f);
        glitchMaterial.SetFloat("_GlitchAmount", randomGlitchAmount);
        glitchMaterial.SetFloat("_GlitchSpeed", 0.3f);
    }
}
