package com.webdigital.money2.integrations;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

@Configuration
public class PixSchedulingConfig {
    @Bean
    public ThreadPoolTaskScheduler pixReconciliationScheduler() {
        return scheduler("pix-reconciliation-", 1);
    }

    @Bean
    public ThreadPoolTaskScheduler pixWhatsappScheduler() {
        return scheduler("pix-whatsapp-", 4);
    }

    // Keep unrelated scheduled jobs on their existing scheduler.
    @Bean
    public ThreadPoolTaskScheduler taskScheduler() {
        return scheduler("scheduling-", 1);
    }

    private ThreadPoolTaskScheduler scheduler(String prefix, int size) {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(size);
        scheduler.setThreadNamePrefix(prefix);
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(15);
        return scheduler;
    }
}
